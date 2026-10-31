require('./src/config/env');
const { z } = require('zod');
const prisma = require('./src/lib/prisma');

async function main() {
  const username = (process.env.TARGET_USER || '').trim();
  if (!username) throw new Error('Username kosong');

  const parsed = z
    .string()
    .trim()
    .toLowerCase()
    .email()
    .safeParse(process.env.NEW_EMAIL || '');
  if (!parsed.success) throw new Error('Format email tidak valid');

  const user = await prisma.user.findUnique({ where: { username } });
  if (!user) throw new Error(`Username "${username}" tidak ditemukan`);

  try {
    await prisma.user.update({ where: { id: user.id }, data: { email: parsed.data } });
  } catch (e) {
    if (e.code === 'P2002') throw new Error('Email sudah dipakai akun lain');
    throw e;
  }

  console.log(`Email untuk "${user.username}" berhasil disimpan.`);
}

main()
  .catch((e) => {
    console.error('Gagal:', e.message);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());