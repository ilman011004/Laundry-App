const { z } = require('zod');
const prisma = require('../lib/prisma');
const { AppError } = require('../middleware/errorHandler');

const idParam = z.object({ id: z.coerce.number().int().positive() });

const createSchema = z.object({
  name: z.string().trim().min(1, 'Nama layanan wajib diisi'),
  pricingType: z.enum(['PER_KG', 'PER_ITEM', 'PACKAGE']),
  price: z.number().int().min(0, 'Harga tidak boleh negatif'),
  isActive: z.boolean().optional(),
  sortOrder: z.number().int().optional(),
});

const updateSchema = createSchema.partial();

const listQuery = z.object({
  includeInactive: z
    .enum(['true', 'false'])
    .default('false')
    .transform((v) => v === 'true'),
});

async function list(req, res) {
  const { includeInactive } = listQuery.parse(req.query);
  const { businessId, isOwner } = req.scope;
  // Hanya OWNER yang boleh melihat layanan nonaktif
  const showAll = includeInactive && isOwner;

  const data = await prisma.service.findMany({
    where: { businessId, ...(showAll ? {} : { isActive: true }) },
    orderBy: [{ sortOrder: 'asc' }, { id: 'asc' }],
  });
  res.json({ data });
}

async function create(req, res) {
  const body = createSchema.parse(req.body);
  const { businessId } = req.scope;

  const dup = await prisma.service.findFirst({ where: { businessId, name: body.name } });
  if (dup) throw new AppError('Nama layanan sudah ada', 409);

  let data;
  try {
    data = await prisma.service.create({ data: { ...body, businessId } });
  } catch (e) {
    // Sementara: keunikan nama di database masih global (diubah di 18c-4)
    if (e.code === 'P2002') throw new AppError('Nama layanan sudah dipakai', 409);
    throw e;
  }
  res.status(201).json({ data });
}

async function update(req, res) {
  const { id } = idParam.parse(req.params);
  const body = updateSchema.parse(req.body);
  const { businessId } = req.scope;

  const current = await prisma.service.findFirst({ where: { id, businessId } });
  if (!current) throw new AppError('Layanan tidak ditemukan', 404);

  if (body.name && body.name !== current.name) {
    const dup = await prisma.service.findFirst({ where: { businessId, name: body.name } });
    if (dup) throw new AppError('Nama layanan sudah dipakai', 409);
  }

  let data;
  try {
    data = await prisma.service.update({ where: { id }, data: body });
  } catch (e) {
    if (e.code === 'P2002') throw new AppError('Nama layanan sudah dipakai', 409);
    throw e;
  }
  res.json({ data });
}

module.exports = { list, create, update };