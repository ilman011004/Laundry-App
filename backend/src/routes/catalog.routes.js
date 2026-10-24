const router = require('express').Router();
const prisma = require('../lib/prisma');
const { authenticate } = require('../middleware/auth');

// Semua yang login boleh membaca katalog (hanya item aktif)
router.get('/', authenticate, async (req, res) => {
  const [services, options] = await Promise.all([
    prisma.service.findMany({
      where: { isActive: true },
      orderBy: [{ sortOrder: 'asc' }, { id: 'asc' }],
    }),
    prisma.serviceOption.findMany({
      where: { isActive: true },
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
});

module.exports = router;