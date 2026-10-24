const { z } = require('zod');
const prisma = require('../lib/prisma');
const { AppError } = require('../middleware/errorHandler');

const idParam = z.object({ id: z.coerce.number().int().positive() });
const addressParam = z.object({
  id: z.coerce.number().int().positive(),
  addressId: z.coerce.number().int().positive(),
});

// Nomor HP: hanya angka, boleh diawali +. Dinormalisasi ke format 08xxxx
function normalizePhone(raw) {
  let p = raw.replace(/[\s\-().]/g, '');
  if (p.startsWith('+62')) p = '0' + p.slice(3);
  else if (p.startsWith('62')) p = '0' + p.slice(2);
  return p;
}

const phoneSchema = z
  .string()
  .trim()
  .min(1, 'Nomor HP wajib diisi')
  .transform(normalizePhone)
  .refine((p) => /^0\d{8,13}$/.test(p), 'Nomor HP tidak valid');

const addressSchema = z.object({
  label: z.string().trim().min(1, 'Label wajib diisi').default('Rumah'),
  address: z.string().trim().min(1, 'Alamat wajib diisi'),
  notes: z.string().trim().optional(),
  isDefault: z.boolean().optional(),
});

const createSchema = z.object({
  name: z.string().trim().min(1, 'Nama wajib diisi'),
  phone: phoneSchema,
  notes: z.string().trim().optional(),
  address: addressSchema.optional(),
});

const updateSchema = z.object({
  name: z.string().trim().min(1).optional(),
  phone: phoneSchema.optional(),
  notes: z.string().trim().nullable().optional(),
});

const updateAddressSchema = z.object({
  label: z.string().trim().min(1).optional(),
  address: z.string().trim().min(1).optional(),
  notes: z.string().trim().nullable().optional(),
  isDefault: z.boolean().optional(),
});

const listQuery = z.object({
  search: z.string().trim().optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

// ---------- Daftar + pencarian ----------
async function list(req, res) {
  const { search, page, limit } = listQuery.parse(req.query);

  const where = search
    ? {
        OR: [
          { name: { contains: search, mode: 'insensitive' } },
          { phone: { contains: normalizePhone(search) } },
        ],
      }
    : {};

  const [total, data] = await Promise.all([
    prisma.customer.count({ where }),
    prisma.customer.findMany({
      where,
      orderBy: { name: 'asc' },
      skip: (page - 1) * limit,
      take: limit,
      include: { addresses: { where: { isDefault: true }, take: 1 } },
    }),
  ]);

  res.json({
    data,
    meta: { page, limit, total, totalPages: Math.ceil(total / limit) },
  });
}

// ---------- Tambah ----------
async function create(req, res) {
  const body = createSchema.parse(req.body);

  const exists = await prisma.customer.findUnique({ where: { phone: body.phone } });
  if (exists) {
    throw new AppError('Nomor HP sudah terdaftar', 409, { customerId: exists.id });
  }

  const customer = await prisma.customer.create({
    data: {
      name: body.name,
      phone: body.phone,
      notes: body.notes,
      addresses: body.address
        ? { create: { ...body.address, isDefault: true } }
        : undefined,
    },
    include: { addresses: true },
  });

  res.status(201).json({ data: customer });
}

// ---------- Detail ----------
async function detail(req, res) {
  const { id } = idParam.parse(req.params);

  const customer = await prisma.customer.findUnique({
    where: { id },
    include: { addresses: { orderBy: [{ isDefault: 'desc' }, { id: 'asc' }] } },
  });
  if (!customer) throw new AppError('Pelanggan tidak ditemukan', 404);

  // Pesanan aktif (belum selesai / belum dibatalkan)
  const activeOrders = await prisma.order.findMany({
    where: { customerId: id, workStatus: { notIn: ['COMPLETED', 'CANCELLED'] } },
    orderBy: { createdAt: 'desc' },
    select: {
      id: true,
      orderNumber: true,
      workStatus: true,
      paymentStatus: true,
      total: true,
      paidAmount: true,
      estimatedDoneAt: true,
    },
  });

  // Total tagihan: sisa bayar semua pesanan yang tidak dibatalkan
  const unpaid = await prisma.order.findMany({
    where: { customerId: id, workStatus: { not: 'CANCELLED' }, paymentStatus: { not: 'PAID' } },
    select: { total: true, paidAmount: true },
  });
  const outstanding = unpaid.reduce((sum, o) => sum + (o.total - o.paidAmount), 0);

  const stats = await prisma.order.aggregate({
    where: { customerId: id, workStatus: { not: 'CANCELLED' } },
    _count: true,
    _sum: { total: true },
  });

  res.json({
    data: {
      ...customer,
      activeOrders,
      summary: {
        totalOrders: stats._count,
        totalSpent: stats._sum.total || 0,
        outstanding,
      },
    },
  });
}

// ---------- Ubah ----------
async function update(req, res) {
  const { id } = idParam.parse(req.params);
  const body = updateSchema.parse(req.body);

  const current = await prisma.customer.findUnique({ where: { id } });
  if (!current) throw new AppError('Pelanggan tidak ditemukan', 404);

  if (body.phone && body.phone !== current.phone) {
    const dup = await prisma.customer.findUnique({ where: { phone: body.phone } });
    if (dup) throw new AppError('Nomor HP sudah dipakai pelanggan lain', 409);
  }

  const customer = await prisma.customer.update({ where: { id }, data: body });
  res.json({ data: customer });
}

// ---------- Alamat ----------
async function addAddress(req, res) {
  const { id } = idParam.parse(req.params);
  const body = addressSchema.parse(req.body);

  const customer = await prisma.customer.findUnique({ where: { id } });
  if (!customer) throw new AppError('Pelanggan tidak ditemukan', 404);

  const count = await prisma.customerAddress.count({ where: { customerId: id } });
  // Alamat pertama otomatis jadi utama
  const makeDefault = count === 0 || body.isDefault === true;

  const address = await prisma.$transaction(async (tx) => {
    if (makeDefault) {
      await tx.customerAddress.updateMany({
        where: { customerId: id },
        data: { isDefault: false },
      });
    }
    return tx.customerAddress.create({
      data: { ...body, customerId: id, isDefault: makeDefault },
    });
  });

  res.status(201).json({ data: address });
}

async function updateAddress(req, res) {
  const { id, addressId } = addressParam.parse(req.params);
  const body = updateAddressSchema.parse(req.body);

  const existing = await prisma.customerAddress.findFirst({
    where: { id: addressId, customerId: id },
  });
  if (!existing) throw new AppError('Alamat tidak ditemukan', 404);

  const address = await prisma.$transaction(async (tx) => {
    if (body.isDefault === true) {
      await tx.customerAddress.updateMany({
        where: { customerId: id },
        data: { isDefault: false },
      });
    }
    // Alamat utama tidak boleh dicabut langsung; pilih alamat lain sebagai utama
    const { isDefault, ...rest } = body;
    return tx.customerAddress.update({
      where: { id: addressId },
      data: { ...rest, ...(isDefault === true ? { isDefault: true } : {}) },
    });
  });

  res.json({ data: address });
}

async function removeAddress(req, res) {
  const { id, addressId } = addressParam.parse(req.params);

  const existing = await prisma.customerAddress.findFirst({
    where: { id: addressId, customerId: id },
  });
  if (!existing) throw new AppError('Alamat tidak ditemukan', 404);

  await prisma.$transaction(async (tx) => {
    await tx.customerAddress.delete({ where: { id: addressId } });

    // Kalau yang dihapus alamat utama, jadikan alamat tertua yang tersisa sebagai utama
    if (existing.isDefault) {
      const next = await tx.customerAddress.findFirst({
        where: { customerId: id },
        orderBy: { id: 'asc' },
      });
      if (next) {
        await tx.customerAddress.update({
          where: { id: next.id },
          data: { isDefault: true },
        });
      }
    }
  });

  res.json({ message: 'Alamat dihapus' });
}

module.exports = { list, create, detail, update, addAddress, updateAddress, removeAddress };