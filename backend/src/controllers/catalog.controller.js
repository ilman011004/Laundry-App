const prisma = require('../lib/prisma');

// Katalog aktif milik usaha yang sedang login
async function get(req, res) {
  const { businessId } = req.scope;

  const [services, options] = await Promise.all([
    prisma.service.findMany({
      where: { businessId, isActive: true },
      orderBy: [{ sortOrder: 'asc' }, { id: 'asc' }],
    }),
    prisma.serviceOption.findMany({
      where: { businessId, isActive: true },
      orderBy: [{ sortOrder: 'asc' }, { id: 'asc' }],
    }),
  ]);

  res.json({
    data: {
      services,
      speeds: options.filter((o) => o.type === 'SPEED'),
      addons: options.filter((o) => o.type === 'ADDON'),
      fulfillments: options.filter((o) => o.type === 'FULFILLMENT'),
    },
  });
}

module.exports = { get };