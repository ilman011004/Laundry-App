require('./src/config/env');
const prisma = require('./src/lib/prisma');

async function main() {
  const rows = await prisma.appSetting.findMany({ where: { key: { startsWith: 'business.' } } });
  if (!rows.length) return console.log('Tidak ada profil lama untuk disalin.');

  const m = Object.fromEntries(rows.map((r) => [r.key.replace('business.', ''), r.value]));
  const first = await prisma.business.findFirst({ orderBy: { id: 'asc' } });
  const updated = await prisma.business.update({
    where: { id: first.id },
    data: { ...(m.name ? { name: m.name } : {}), address: m.address || '', phone: m.phone || '' },
  });
  console.log('Profil disalin ke usaha:', updated.name, '|', updated.address, '|', updated.phone);
}

main().catch(console.error).finally(() => prisma.$disconnect());
