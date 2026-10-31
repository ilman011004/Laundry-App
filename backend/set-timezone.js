require('./src/config/env');
const prisma = require('./src/lib/prisma');

async function main() {
  const r = await prisma.business.updateMany({ data: { timezone: 'Asia/Makassar' } });
  console.log(`${r.count} usaha diset ke Asia/Makassar`);
}

main().catch(console.error).finally(() => prisma.$disconnect());
