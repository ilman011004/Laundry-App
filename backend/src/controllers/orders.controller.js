const { z } = require('zod');
const prisma = require('../lib/prisma');
const { AppError } = require('../middleware/errorHandler');
const { calculate } = require('../services/pricing.service');
const { TZ_OFFSET_HOURS } = require('../utils/time');

const idParam = z.object({ id: z.coerce.number().int().positive() });

const itemSchema = z.object({
  serviceId: z.number().int().positive(),
  quantity: z.number().positive('Jumlah harus lebih dari 0').max(1000),
  notes: z.string().trim().optional(),
  addonIds: z.array(z.number().int().positive()).optional(),
});

const orderInputSchema = z.object({
  customerId: z.number().int().positive().optional(),
  items: z.array(itemSchema).min(1, 'Minimal satu layanan'),
  speedId: z.number().int().positive().optional(),
  fulfillmentId: z.number().int().positive().optional(),
  discount: z.number().int().min(0).optional(),
  notes: z.string().trim().optional(),
});

const listQuery = z.object({
  search: z.string().trim().optional(),
  workStatus: z
    .enum(['RECEIVED', 'WASHING', 'DRYING', 'IRONING', 'READY', 'COMPLETED', 'CANCELLED'])
    .optional(),
  paymentStatus: z.enum(['UNPAID', 'PARTIAL', 'PAID']).optional(),
  customerId: z.coerce.number().int().positive().optional(),
  view: z.enum(['inProgress', 'ready', 'completedToday', 'unpaid']).optional(),
  from: z.coerce.date().optional(),
  to: z.coerce.date().optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

// Relasi yang ikut dimuat pada detail dan hasil pembuatan pesanan
const orderInclude = {
  customer: { select: { id: true, name: true, phone: true } },
  createdBy: { select: { id: true, name: true } },
  items: { include: { addons: true }, orderBy: { id: 'asc' } },
  history: {
    orderBy: { id: 'asc' },
    include: { changedBy: { select: { id: true, name: true } } },
  },
  payments: { orderBy: { id: 'asc' } },
  deliveries: {
    orderBy: { id: 'asc' },
    include: { courier: { select: { id: true, name: true } } },
  },
};

// Nomor order: LDR-YYMMDD-0001 (urut per hari, mengikuti zona waktu di utils/time.js)
async function generateOrderNumber(tx) {
  const now = new Date(Date.now() + TZ_OFFSET_HOURS * 3600 * 1000);
  const yy = String(now.getUTCFullYear()).slice(2);
  const mm = String(now.getUTCMonth() + 1).padStart(2, '0');
  const dd = String(now.getUTCDate()).padStart(2, '0');
  const prefix = `LDR-${yy}${mm}${dd}-`;

  const last = await tx.order.findFirst({
    where: { orderNumber: { startsWith: prefix } },
    orderBy: { orderNumber: 'desc' },
    select: { orderNumber: true },
  });
  const next = last ? Number(last.orderNumber.slice(prefix.length)) + 1 : 1;
  return prefix + String(next).padStart(4, '0');
}

// ---------- Preview ----------
async function preview(req, res) {
  const body = orderInputSchema.parse(req.body);
  const result = await calculate(body);

  let estimatedDoneAt = null;
  if (result.speed && result.speed.hours) {
    estimatedDoneAt = new Date(Date.now() + result.speed.hours * 3600 * 1000);
  }
  res.json({ data: { ...result, estimatedDoneAt } });
}

// ---------- Buat pesanan ----------
async function create(req, res) {
  const body = orderInputSchema.parse(req.body);
  if (!body.customerId) throw new AppError('Pelanggan wajib dipilih', 422);

  const customer = await prisma.customer.findUnique({ where: { id: body.customerId } });
  if (!customer) throw new AppError('Pelanggan tidak ditemukan', 404);

  // Harga dihitung ulang di server, angka dari klien tidak dipercaya
  const calc = await calculate(body);

  const receivedAt = new Date();
  const estimatedDoneAt =
    calc.speed && calc.speed.hours
      ? new Date(receivedAt.getTime() + calc.speed.hours * 3600 * 1000)
      : null;

  // Coba ulang bila nomor order bentrok (dua kasir menyimpan bersamaan)
  let order;
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      order = await prisma.$transaction(async (tx) => {
        const orderNumber = await generateOrderNumber(tx);

        return tx.order.create({
          data: {
            orderNumber,
            customerId: body.customerId,
            createdById: req.user.id,
            receiveMethod: calc.fulfillment ? calc.fulfillment.receiveMethod : 'SELF_PICKUP',
            speedName: calc.speed ? calc.speed.name : null,
            speedFee: calc.speedFee,
            speedHours: calc.speed ? calc.speed.hours : null,
            fulfillmentName: calc.fulfillment ? calc.fulfillment.name : null,
            deliveryFee: calc.deliveryFee,
            subtotal: calc.subtotal,
            discount: calc.discount,
            total: calc.total,
            notes: body.notes,
            receivedAt,
            estimatedDoneAt,
            items: {
              create: calc.items.map((it) => ({
                serviceId: it.serviceId,
                serviceName: it.serviceName,
                pricingType: it.pricingType,
                unitPrice: it.unitPrice,
                quantity: it.quantity,
                lineTotal: it.lineTotal,
                notes: it.notes,
                addons: { create: it.addons },
              })),
            },
            history: {
              create: {
                fromStatus: null,
                toStatus: 'RECEIVED',
                changedById: req.user.id,
                note: 'Pesanan dibuat',
              },
            },
          },
          include: orderInclude,
        });
      });
      break;
    } catch (e) {
      if (e.code === 'P2002' && attempt < 2) continue;
      throw e;
    }
  }

  res.status(201).json({ data: order });
}

// Awal hari ini menurut waktu usaha (Asia/Makassar, UTC+8)
function startOfDayLocal() {
  const H = 3600 * 1000;
  const l = new Date(Date.now() + 8 * H);
  return new Date(Date.UTC(l.getUTCFullYear(), l.getUTCMonth(), l.getUTCDate()) - 8 * H);
}

function viewCondition(view) {
  switch (view) {
    case 'inProgress':
      return { workStatus: { in: ['RECEIVED', 'WASHING', 'DRYING', 'IRONING'] } };
    case 'ready':
      return { workStatus: 'READY' };
    case 'completedToday':
      return { workStatus: 'COMPLETED', completedAt: { gte: startOfDayLocal() } };
    case 'unpaid':
      return { workStatus: { not: 'CANCELLED' }, paymentStatus: { not: 'PAID' } };
    default:
      return null;
  }
}


// ---------- Daftar ----------
async function list(req, res) {
  const q = listQuery.parse(req.query);

  const where = {};
  if (q.workStatus) where.workStatus = q.workStatus;
  if (q.paymentStatus) where.paymentStatus = q.paymentStatus;
  if (q.customerId) where.customerId = q.customerId;
  if (q.from || q.to) {
    where.createdAt = {};
    if (q.from) where.createdAt.gte = q.from;
    if (q.to) where.createdAt.lte = q.to;
  }
  const vc = viewCondition(q.view);
  if (vc) where.AND = [vc];
  if (q.search) {
    where.OR = [
      { orderNumber: { contains: q.search, mode: 'insensitive' } },
      { customer: { name: { contains: q.search, mode: 'insensitive' } } },
      { customer: { phone: { contains: q.search } } },
    ];
  }

  const [total, data] = await Promise.all([
    prisma.order.count({ where }),
    prisma.order.findMany({
      where,
      orderBy: { id: 'desc' },
      skip: (q.page - 1) * q.limit,
      take: q.limit,
      select: {
        id: true,
        orderNumber: true,
        workStatus: true,
        paymentStatus: true,
        receiveMethod: true,
        speedName: true,
        total: true,
        paidAmount: true,
        receivedAt: true,
        estimatedDoneAt: true,
        customer: { select: { id: true, name: true, phone: true } },
      },
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
  const order = await prisma.order.findUnique({ where: { id }, include: orderInclude });
  if (!order) throw new AppError('Pesanan tidak ditemukan', 404);

  res.json({ data: { ...order, remaining: order.total - order.paidAmount } });
}

module.exports = { preview, create, list, detail };