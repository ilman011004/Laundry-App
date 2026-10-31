const { z } = require('zod');
const prisma = require('../lib/prisma');
const { AppError } = require('../middleware/errorHandler');
const { outletScope } = require('../middleware/scope');
const t = require('../utils/time');

const idParam = z.object({ id: z.coerce.number().int().positive() });
const dateRe = /^\d{4}-\d{2}-\d{2}$/;

// Jenis pengantaran yang diizinkan untuk tiap cara penerimaan pesanan
const ALLOWED_METHODS = {
  PICKUP: ['PICKUP_DELIVERY'],
  DROPOFF: ['DELIVERY', 'PICKUP_DELIVERY'],
};
const TYPE_LABEL = { PICKUP: 'jemput', DROPOFF: 'antar' };

const TRANSITIONS = {
  SCHEDULED: ['ON_THE_WAY', 'DONE', 'CANCELLED'],
  ON_THE_WAY: ['DONE', 'CANCELLED'],
  DONE: [],
  CANCELLED: [],
};

const deliveryInclude = {
  order: {
    select: {
      id: true,
      orderNumber: true,
      workStatus: true,
      customer: { select: { id: true, name: true, phone: true } },
    },
  },
  courier: { select: { id: true, name: true } },
};

const addressFields = {
  addressId: z.number().int().positive().optional(),
  address: z.string().trim().min(5, 'Alamat minimal 5 karakter').max(300).optional(),
};

const createSchema = z.object({
  orderId: z.number().int().positive(),
  type: z.enum(['PICKUP', 'DROPOFF']),
  ...addressFields,
  scheduledAt: z.coerce.date().optional(),
  courierId: z.number().int().positive().optional(),
  notes: z.string().trim().max(200).optional(),
});

const updateSchema = z
  .object({
    ...addressFields,
    scheduledAt: z.coerce.date().optional(),
    courierId: z.number().int().positive().nullable().optional(),
    notes: z.string().trim().max(200).optional(),
  })
  .refine((o) => Object.keys(o).length > 0, 'Tidak ada data yang diubah');

const statusSchema = z.object({
  status: z.enum(['ON_THE_WAY', 'DONE', 'CANCELLED']),
});

const listQuery = z.object({
  status: z.enum(['SCHEDULED', 'ON_THE_WAY', 'DONE', 'CANCELLED']).optional(),
  type: z.enum(['PICKUP', 'DROPOFF']).optional(),
  courierId: z.coerce.number().int().positive().optional(),
  orderId: z.coerce.number().int().positive().optional(),
  from: z.string().regex(dateRe, 'Format tanggal harus YYYY-MM-DD').optional(),
  to: z.string().regex(dateRe, 'Format tanggal harus YYYY-MM-DD').optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

// ---------- Fungsi bantu ----------
function checkSchedule(date, tz) {
  if (date && date < t.startOfDay(new Date(), tz)) {
    throw new AppError('Jadwal tidak boleh sebelum hari ini', 400);
  }
}

// Kurir harus akun aktif milik usaha yang sama
async function checkCourier(courierId, businessId) {
  if (!courierId) return;
  const u = await prisma.user.findFirst({
    where: { id: courierId, businessId, isActive: true },
    select: { id: true },
  });
  if (!u) throw new AppError('Kurir tidak ditemukan atau tidak aktif', 400);
}

// Alamat dari addressId, teks manual, atau (jika useDefault) alamat default pelanggan
async function resolveAddress(customerId, input, useDefault) {
  if (input.addressId) {
    const a = await prisma.customerAddress.findFirst({
      where: { id: input.addressId, customerId },
    });
    if (!a) throw new AppError('Alamat tidak ditemukan untuk pelanggan ini', 400);
    return `${a.label}: ${a.address}`;
  }
  if (input.address) return input.address;

  if (useDefault) {
    const a = await prisma.customerAddress.findFirst({
      where: { customerId },
      orderBy: [{ isDefault: 'desc' }, { id: 'asc' }],
    });
    if (!a) {
      throw new AppError('Alamat wajib diisi (pelanggan belum punya alamat tersimpan)', 400);
    }
    return `${a.label}: ${a.address}`;
  }
  return null;
}

// ---------- Jadwalkan ----------
async function create(req, res) {
  const body = createSchema.parse(req.body);
  const { businessId, timezone } = req.scope;

  const order = await prisma.order.findFirst({
    where: { id: body.orderId, ...outletScope(req.scope) },
    select: { id: true, customerId: true, workStatus: true, receiveMethod: true },
  });
  if (!order) throw new AppError('Pesanan tidak ditemukan', 404);
  if (order.workStatus === 'CANCELLED' || order.workStatus === 'COMPLETED') {
    throw new AppError('Pesanan sudah selesai atau dibatalkan, tidak bisa dijadwalkan', 409);
  }
  if (!ALLOWED_METHODS[body.type].includes(order.receiveMethod)) {
    throw new AppError(`Pesanan ini tidak memakai layanan ${TYPE_LABEL[body.type]}`, 400);
  }

  const duplicate = await prisma.delivery.findFirst({
    where: {
      orderId: order.id,
      type: body.type,
      status: { in: ['SCHEDULED', 'ON_THE_WAY', 'DONE'] },
    },
    select: { id: true },
  });
  if (duplicate) {
    throw new AppError(`Jadwal ${TYPE_LABEL[body.type]} untuk pesanan ini sudah ada`, 409);
  }

  checkSchedule(body.scheduledAt, timezone);
  await checkCourier(body.courierId, businessId);
  const addressSnapshot = await resolveAddress(order.customerId, body, true);

  const delivery = await prisma.delivery.create({
    data: {
      orderId: order.id,
      type: body.type,
      addressSnapshot,
      scheduledAt: body.scheduledAt,
      courierId: body.courierId,
      notes: body.notes,
    },
    include: deliveryInclude,
  });

  res.status(201).json({ data: delivery });
}

// ---------- Daftar ----------
async function list(req, res) {
  const q = listQuery.parse(req.query);
  const tz = req.scope.timezone;

  const where = { order: outletScope(req.scope) };
  if (q.status) where.status = q.status;
  if (q.type) where.type = q.type;
  if (q.courierId) where.courierId = q.courierId;
  if (q.orderId) where.orderId = q.orderId;

  if (q.from || q.to) {
    const start = q.from ? t.parseLocalDate(q.from, tz) : null;
    const end = q.to ? t.addDays(t.parseLocalDate(q.to, tz), 1) : null;
    if (q.from && t.dayKey(start, tz) !== q.from) throw new AppError('Tanggal awal tidak valid', 400);
    if (q.to && t.dayKey(t.addDays(end, -1), tz) !== q.to) {
      throw new AppError('Tanggal akhir tidak valid', 400);
    }
    where.scheduledAt = {};
    if (start) where.scheduledAt.gte = start;
    if (end) where.scheduledAt.lt = end;
  }

  const [total, data] = await Promise.all([
    prisma.delivery.count({ where }),
    prisma.delivery.findMany({
      where,
      orderBy: [{ scheduledAt: { sort: 'asc', nulls: 'last' } }, { id: 'desc' }],
      skip: (q.page - 1) * q.limit,
      take: q.limit,
      include: deliveryInclude,
    }),
  ]);

  res.json({
    data,
    meta: { page: q.page, limit: q.limit, total, totalPages: Math.ceil(total / q.limit) },
  });
}

// ---------- Detail ----------
async function detail(req, res) {
  const { id } = idParam.parse(req.params);
  const delivery = await prisma.delivery.findFirst({
    where: { id, order: outletScope(req.scope) },
    include: deliveryInclude,
  });
  if (!delivery) throw new AppError('Pengantaran tidak ditemukan', 404);
  res.json({ data: delivery });
}

// ---------- Ubah jadwal, kurir, alamat ----------
async function update(req, res) {
  const { id } = idParam.parse(req.params);
  const body = updateSchema.parse(req.body);
  const { businessId, timezone } = req.scope;

  const current = await prisma.delivery.findFirst({
    where: { id, order: outletScope(req.scope) },
    select: { status: true, order: { select: { customerId: true } } },
  });
  if (!current) throw new AppError('Pengantaran tidak ditemukan', 404);
  if (current.status !== 'SCHEDULED') {
    throw new AppError('Hanya jadwal berstatus SCHEDULED yang bisa diubah', 409);
  }

  checkSchedule(body.scheduledAt, timezone);
  await checkCourier(body.courierId || undefined, businessId);
  const addressSnapshot = await resolveAddress(current.order.customerId, body, false);

  const data = {};
  if (body.scheduledAt !== undefined) data.scheduledAt = body.scheduledAt;
  if (body.courierId !== undefined) data.courierId = body.courierId;
  if (body.notes !== undefined) data.notes = body.notes;
  if (addressSnapshot) data.addressSnapshot = addressSnapshot;

  const changed = await prisma.delivery.updateMany({ where: { id, status: 'SCHEDULED' }, data });
  if (changed.count === 0) {
    throw new AppError('Status pengantaran baru saja berubah, muat ulang lalu coba lagi', 409);
  }

  const delivery = await prisma.delivery.findUnique({ where: { id }, include: deliveryInclude });
  res.json({ data: delivery });
}

// ---------- Ubah status ----------
async function setStatus(req, res) {
  const { id } = idParam.parse(req.params);
  const body = statusSchema.parse(req.body);

  const current = await prisma.delivery.findFirst({
    where: { id, order: outletScope(req.scope) },
    select: { status: true },
  });
  if (!current) throw new AppError('Pengantaran tidak ditemukan', 404);

  if (!TRANSITIONS[current.status].includes(body.status)) {
    throw new AppError(`Status tidak bisa diubah dari ${current.status} ke ${body.status}`, 409);
  }

  const changed = await prisma.delivery.updateMany({
    where: { id, status: current.status },
    data: { status: body.status },
  });
  if (changed.count === 0) {
    throw new AppError('Status pengantaran baru saja berubah, muat ulang lalu coba lagi', 409);
  }

  const delivery = await prisma.delivery.findUnique({ where: { id }, include: deliveryInclude });
  res.json({ data: delivery });
}

module.exports = { create, list, detail, update, setStatus };