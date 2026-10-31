require('./src/config/env');
const crypto = require('crypto');
const prisma = require('./src/lib/prisma');

// Tanpa huruf dan angka yang mirip (0, O, 1, I) supaya mudah dibaca dan diketik
const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

function randomCode(length = 6) {
  const bytes = crypto.randomBytes(length);
  return Array.from(bytes, (b) => ALPHABET[b % ALPHABET.length]).join('');
}

async function uniqueCode() {
  for (let i = 0; i < 10; i++) {
    const code = randomCode();
    const taken = await prisma.business.findUnique({ where: { code } });
    if (!taken) return code;
  }
  throw new Error('Gagal membuat kode usaha yang unik');
}

async function main() {
  const total = await prisma.business.count();
  if (total > 1) {
    throw new Error('Sudah ada lebih dari satu usaha. Skrip ini hanya untuk migrasi data awal.');
  }

  // 1. Usaha (nama, alamat, telepon diambil dari pengaturan lama)
  let business = await prisma.business.findFirst();
  if (!business) {
    const rows = await prisma.appSetting.findMany({
      where: { key: { startsWith: 'business.' } },
    });
    const s = Object.fromEntries(rows.map((r) => [r.key.replace('business.', ''), r.value]));

    business = await prisma.business.create({
      data: {
        name: s.name || 'Laundry',
        code: await uniqueCode(),
        address: s.address || '',
        phone: s.phone || '',
      },
    });
    console.log(`Usaha dibuat: ${business.name}`);
  } else {
    console.log(`Memakai usaha yang sudah ada: ${business.name}`);
  }

  // 2. Outlet utama
  let outlet = await prisma.outlet.findFirst({
    where: { businessId: business.id },
    orderBy: { id: 'asc' },
  });
  if (!outlet) {
    outlet = await prisma.outlet.create({
      data: {
        businessId: business.id,
        name: 'Outlet Utama',
        address: business.address,
        phone: business.phone,
      },
    });
    console.log('Outlet dibuat: Outlet Utama');
  }

  // 3. Pindahkan semua data lama ke usaha dan outlet ini
  const bid = business.id;
  const oid = outlet.id;
  const unset = { OR: [{ businessId: null }, { outletId: null }] };
  const scope = { businessId: bid, outletId: oid };

  const results = await prisma.$transaction([
    prisma.user.updateMany({ where: { businessId: null }, data: { businessId: bid } }),
    prisma.user.updateMany({
      where: { outletId: null, role: { name: { not: 'OWNER' } } },
      data: { outletId: oid },
    }),
    prisma.customer.updateMany({ where: { businessId: null }, data: { businessId: bid } }),
    prisma.service.updateMany({ where: { businessId: null }, data: { businessId: bid } }),
    prisma.serviceOption.updateMany({ where: { businessId: null }, data: { businessId: bid } }),
    prisma.order.updateMany({ where: unset, data: scope }),
    prisma.expense.updateMany({ where: unset, data: scope }),
    prisma.cashDeposit.updateMany({ where: unset, data: scope }),
  ]);

  const labels = [
    'pengguna (usaha)',
    'pengguna (outlet kasir)',
    'pelanggan',
    'layanan',
    'opsi layanan',
    'pesanan',
    'pengeluaran',
    'setoran kas',
  ];
  console.log('Data yang diperbarui:');
  console.table(labels.map((data, i) => ({ data, jumlah: results[i].count })));

  // 4. Pemeriksaan: tidak boleh ada yang tersisa
  const remaining = {
    pengguna: await prisma.user.count({ where: { businessId: null } }),
    pelanggan: await prisma.customer.count({ where: { businessId: null } }),
    layanan: await prisma.service.count({ where: { businessId: null } }),
    opsi: await prisma.serviceOption.count({ where: { businessId: null } }),
    pesanan: await prisma.order.count({ where: unset }),
    pengeluaran: await prisma.expense.count({ where: unset }),
    setoran: await prisma.cashDeposit.count({ where: unset }),
  };
  console.log('Sisa yang belum punya usaha (semuanya harus 0):');
  console.table([remaining]);

  console.log(`Kode usaha untuk login kasir: ${business.code}`);
}

main()
  .catch((e) => {
    console.error('Gagal:', e.message);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());