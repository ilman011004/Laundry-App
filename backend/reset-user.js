require('./src/config/env');
const bcrypt = require('bcryptjs');
const prisma = require('./src/lib/prisma');

async function main() {
  // Mode daftar: node reset-user.js --list
  if (process.argv.includes('--list')) {
    const users = await prisma.user.findMany({
      include: { role: true },
      orderBy: { id: 'asc' },
    });
    console.table(
      users.map((u) => ({
        id: u.id,
        nama: u.name,
        username: u.username,
        peran: u.role.name,
        aktif: u.isActive,
      }))
    );
    return;
  }

  const username = (process.env.TARGET_USER || '').trim();
  const password = process.env.NEW_PASS || '';

  if (!username) throw new Error('Username kosong');
  if (password.length < 8) throw new Error('Password minimal 8 karakter');

  const user = await prisma.user.findUnique({
    where: { username },
    include: { role: true },
  });
  if (!user) throw new Error(`Username "${username}" tidak ditemukan`);

  await prisma.user.update({
    where: { id: user.id },
    data: { passwordHash: await bcrypt.hash(password, 12) },
  });

  console.log(`Password "${user.username}" (${user.role.name}) berhasil direset.`);
  if (!user.isActive) {
    console.log('PERHATIAN: akun ini masih NONAKTIF, jadi belum bisa login.');
  }
}

main()
  .catch((e) => {
    console.error('Gagal:', e.message);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());