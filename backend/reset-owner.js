require('dotenv').config();
const { PrismaClient } = require('@prisma/client');
const bcrypt = require('bcryptjs');

const prisma = new PrismaClient();
const newPassword = process.argv[2];

if (!newPassword || newPassword.length < 8) {
  console.error('Pakai: node reset-owner.js PasswordBaru (minimal 8 karakter)');
  process.exit(1);
}

(async () => {
  const user = await prisma.user.update({
    where: { username: process.env.SEED_OWNER_USERNAME || 'owner' },
    data: { passwordHash: await bcrypt.hash(newPassword, 12) },
  });
  console.log(`Password ${user.username} berhasil direset.`);
})()
  .catch((e) => console.error(e.message))
  .finally(() => prisma.$disconnect());