const { z } = require('zod');
const prisma = require('../lib/prisma');
const { AppError } = require('../middleware/errorHandler');

const idParam = z.object({ id: z.coerce.number().int().positive() });

// Skema dasar: TANPA nilai bawaan, supaya aman dipakai untuk PATCH
const baseSchema = z.object({
  type: z.enum(['SPEED', 'ADDON', 'FULFILLMENT']),
  name: z.string().trim().min(1, 'Nama opsi wajib diisi'),
  priceMode: z.enum(['FIXED', 'PERCENT']),
  price: z.number().int().min(0, 'Harga tidak boleh negatif'),
  durationHours: z.number().int().min(1).nullable().optional(),
  isActive: z.boolean().optional(),
  sortOrder: z.number().int().optional(),
});

// Persen tidak boleh lebih dari 1000 (10x lipat) agar tidak salah ketik
function checkPercent(data) {
  if (data.priceMode === 'PERCENT' && data.price > 1000) {
    throw new AppError('Persentase tidak masuk akal (maksimal 1000)', 422);
  }
}

// Saat membuat: priceMode boleh dikosongkan, otomatis FIXED
const createSchema = baseSchema.extend({
  priceMode: z.enum(['FIXED', 'PERCENT']).default('FIXED'),
});

// Saat mengubah: type tidak boleh diganti, semua field opsional
// dan tidak ada nilai bawaan, jadi field yang tidak dikirim tidak berubah
const updateSchema = baseSchema.omit({ type: true }).partial();

const listQuery = z.object({
  type: z.enum(['SPEED', 'ADDON', 'FULFILLMENT']).optional(),
  includeInactive: z
    .enum(['true', 'false'])
    .default('false')
    .transform((v) => v === 'true'),
});

async function list(req, res) {
  const { type, includeInactive } = listQuery.parse(req.query);
  const showAll = includeInactive && req.user.role === 'OWNER';

  const data = await prisma.serviceOption.findMany({
    where: {
      ...(type ? { type } : {}),
      ...(showAll ? {} : { isActive: true }),
    },
    orderBy: [{ type: 'asc' }, { sortOrder: 'asc' }, { id: 'asc' }],
  });
  res.json({ data });
}

async function create(req, res) {
  const body = createSchema.parse(req.body);
  checkPercent(body);

  const dup = await prisma.serviceOption.findUnique({
    where: { type_name: { type: body.type, name: body.name } },
  });
  if (dup) throw new AppError('Opsi dengan nama itu sudah ada pada tipe yang sama', 409);

  const data = await prisma.serviceOption.create({ data: body });
  res.status(201).json({ data });
}

async function update(req, res) {
  const { id } = idParam.parse(req.params);
  const body = updateSchema.parse(req.body);

  const current = await prisma.serviceOption.findUnique({ where: { id } });
  if (!current) throw new AppError('Opsi tidak ditemukan', 404);

  checkPercent({
    priceMode: body.priceMode ?? current.priceMode,
    price: body.price ?? current.price,
  });

  if (body.name && body.name !== current.name) {
    const dup = await prisma.serviceOption.findUnique({
      where: { type_name: { type: current.type, name: body.name } },
    });
    if (dup) throw new AppError('Nama opsi sudah dipakai pada tipe yang sama', 409);
  }

  const data = await prisma.serviceOption.update({ where: { id }, data: body });
  res.json({ data });
}

module.exports = { list, create, update };