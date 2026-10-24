require('dotenv').config();
const { PrismaClient } = require('@prisma/client');
const bcrypt = require('bcryptjs');

const prisma = new PrismaClient();

async function main() {
  // 1. Role
  const roleNames = ['OWNER', 'CASHIER', 'OPERATOR'];
  const roles = {};
  for (const name of roleNames) {
    roles[name] = await prisma.role.upsert({
      where: { name },
      update: {},
      create: { name },
    });
  }

  // 2. Akun pemilik
  const username = process.env.SEED_OWNER_USERNAME || 'owner';
  const password = process.env.SEED_OWNER_PASSWORD;
  if (!password) throw new Error('SEED_OWNER_PASSWORD belum diisi di .env');

  await prisma.user.upsert({
    where: { username },
    update: {},
    create: {
      name: process.env.SEED_OWNER_NAME || 'Pemilik Laundry',
      username,
      passwordHash: await bcrypt.hash(password, 12),
      roleId: roles.OWNER.id,
    },
  });

  // 3. Layanan contoh
  const services = [
    { name: 'Cuci Kering',  pricingType: 'PER_KG',   price: 5000,  sortOrder: 1 },
    { name: 'Cuci Setrika', pricingType: 'PER_KG',   price: 7000,  sortOrder: 2 },
    { name: 'Setrika Saja', pricingType: 'PER_KG',   price: 4000,  sortOrder: 3 },
    { name: 'Sepatu',       pricingType: 'PER_ITEM', price: 35000, sortOrder: 4 },
    { name: 'Selimut',      pricingType: 'PER_ITEM', price: 25000, sortOrder: 5 },
  ];
  for (const s of services) {
    await prisma.service.upsert({
      where: { name: s.name },
      update: {},
      create: s,
    });
  }

  // 4. Opsi: kecepatan, add-on, penerimaan
  const options = [
    { type: 'SPEED', name: 'Normal',   priceMode: 'FIXED',   price: 0,   durationHours: 72, sortOrder: 1 },
    { type: 'SPEED', name: 'Sedang',   priceMode: 'PERCENT', price: 25,  durationHours: 48, sortOrder: 2 },
    { type: 'SPEED', name: 'Express',  priceMode: 'PERCENT', price: 50,  durationHours: 24, sortOrder: 3 },
    { type: 'SPEED', name: 'Same Day', priceMode: 'PERCENT', price: 100, durationHours: 8,  sortOrder: 4 },

    { type: 'ADDON', name: 'Pewangi Premium', priceMode: 'FIXED', price: 3000, sortOrder: 1 },
    { type: 'ADDON', name: 'Deterjen Khusus', priceMode: 'FIXED', price: 5000, sortOrder: 2 },

    { type: 'FULFILLMENT', name: 'Ambil Sendiri',    priceMode: 'FIXED', price: 0,     sortOrder: 1 },
    { type: 'FULFILLMENT', name: 'Diantar',          priceMode: 'FIXED', price: 5000,  sortOrder: 2 },
    { type: 'FULFILLMENT', name: 'Jemput dan Antar', priceMode: 'FIXED', price: 10000, sortOrder: 3 },
  ];
  for (const o of options) {
    await prisma.serviceOption.upsert({
      where: { type_name: { type: o.type, name: o.name } },
      update: {},
      create: o,
    });
  }

  console.log('Seed selesai.');
  console.log(`Login awal -> username: ${username}`);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());