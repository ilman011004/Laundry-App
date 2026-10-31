require('./src/config/env');
const prisma = require('./src/lib/prisma');

async function main() {
  const rows = await prisma.$queryRawUnsafe(`
    SELECT 'customers' AS tabel, COUNT(*)::int AS total, COUNT(business_id)::int AS terisi FROM customers
    UNION ALL SELECT 'services', COUNT(*)::int, COUNT(business_id)::int FROM services
    UNION ALL SELECT 'service_options', COUNT(*)::int, COUNT(business_id)::int FROM service_options
    UNION ALL SELECT 'orders', COUNT(*)::int, COUNT(business_id)::int FROM orders
    UNION ALL SELECT 'orders_outlet', COUNT(*)::int, COUNT(outlet_id)::int FROM orders
    UNION ALL SELECT 'expenses', COUNT(*)::int, COUNT(business_id)::int FROM expenses
    UNION ALL SELECT 'cash_deposits', COUNT(*)::int, COUNT(business_id)::int FROM cash_deposits
    UNION ALL SELECT 'users', COUNT(*)::int, COUNT(business_id)::int FROM users
  `);
  console.table(rows);
}

main().catch(console.error).finally(() => prisma.$disconnect());
