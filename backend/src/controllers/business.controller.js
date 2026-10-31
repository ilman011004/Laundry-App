const { z } = require('zod');
const prisma = require('../lib/prisma');
const { AppError } = require('../middleware/errorHandler');

const schema = z.object({
  name: z.string().trim().min(1, 'Nama usaha wajib diisi').max(60),
  address: z.string().trim().max(200).default(''),
  phone: z.string().trim().max(30).default(''),
  timezone: z.enum(['Asia/Jakarta', 'Asia/Makassar', 'Asia/Jayapura']).optional(),
});

const select = { id: true, name: true, address: true, phone: true, timezone: true };

async function get(req, res) {
  const data = await prisma.business.findUnique({
    where: { id: req.scope.businessId },
    select,
  });
  if (!data) throw new AppError('Usaha tidak ditemukan', 404);
  res.json({ data });
}

async function update(req, res) {
  const body = schema.parse(req.body);

  const data = await prisma.business.update({
    where: { id: req.scope.businessId },
    data: {
      name: body.name,
      address: body.address,
      phone: body.phone,
      ...(body.timezone ? { timezone: body.timezone } : {}),
    },
    select,
  });
  res.json({ data });
}

module.exports = { get, update };