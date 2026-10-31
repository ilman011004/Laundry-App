
require('./src/config/env');
const prisma = require('./src/lib/prisma');

async function main() {
  // 1. Baris tanpa usaha dimasukkan ke usaha tertua
  for (const t of ['users', 'customers', 'services', 'service_options', 'orders', 'expenses', 'cash_deposits']) {
    await prisma.$executeRawUnsafe(
      `UPDATE ${t} SET business_id = (SELECT MIN(id) FROM businesses) WHERE business_id IS NULL`
    );
  }
  // 2. Baris tanpa outlet dimasukkan ke outlet tertua usahanya
  for (const t of ['orders', 'expenses', 'cash_deposits']) {
    await prisma.$executeRawUnsafe(
      `UPDATE ${t} x SET outlet_id = (SELECT o.id FROM outlets o WHERE o.business_id = x.business_id ORDER BY o.id LIMIT 1) WHERE x.outlet_id IS NULL`
    );
  }

  // 3. Pemeriksaan: harus 0 semua
  const bad = await prisma.$queryRawUnsafe(`
    SELECT 'pesanan beda usaha dengan pelanggan' AS cek, COUNT(*)::int AS jumlah
      FROM orders o JOIN customers c ON c.id = o.customer_id WHERE c.business_id <> o.business_id
    UNION ALL SELECT 'pesanan beda usaha dengan outlet', COUNT(*)::int
      FROM orders o JOIN outlets t ON t.id = o.outlet_id WHERE t.business_id <> o.business_id
    UNION ALL SELECT 'pengguna beda usaha dengan outlet', COUNT(*)::int
      FROM users u JOIN outlets t ON t.id = u.outlet_id WHERE t.business_id <> u.business_id
  `);
  console.table(bad);

  // 4. Sebaran data per usaha
  const per = await prisma.$queryRawUnsafe(`
    SELECT b.id, b.name, b.code,
      (SELECT COUNT(*)::int FROM customers WHERE business_id = b.id) AS pelanggan,
      (SELECT COUNT(*)::int FROM services WHERE business_id = b.id) AS layanan,
      (SELECT COUNT(*)::int FROM service_options WHERE business_id = b.id) AS opsi,
      (SELECT COUNT(*)::int FROM orders WHERE business_id = b.id) AS pesanan,
      (SELECT COUNT(*)::int FROM users WHERE business_id = b.id) AS pengguna
    FROM businesses b ORDER BY b.id
  `);
  console.table(per);
}

main().catch(console.error).finally(() => prisma.$disconnect());


