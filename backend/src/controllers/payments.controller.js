const { z } = require('zod');
const prisma = require('../lib/prisma');
const { AppError } = require('../middleware/errorHandler');
const { outletScope } = require('../middleware/scope');

const idParam = z.object({ id: z.coerce.number().int().positive() });

const paymentSchema = z.object({
  amount: z.number().int().positive('Nominal harus lebih dari 0'),
  method: z.enum(['CASH', 'TRANSFER', 'QRIS']),
  note: z.string().trim().max(200).optional(),
});

function derivePaymentStatus(paid, total) {
  if (paid <= 0) return 'UNPAID';
  if (paid >= total) return 'PAID';
  return 'PARTIAL';
}

// ---------- Catat pembayaran ----------
async function create(req, res) {
  const { id } = idParam.parse(req.params);
  const body = paymentSchema.parse(req.body);
  const sc = outletScope(req.scope);

  const result = await prisma.$transaction(async (tx) => {
    const order = await tx.order.findFirst({
      where: { id, ...sc },
      select: { id: true, total: true, paidAmount: true, workStatus: true },
    });
    if (!order) throw new AppError('Pesanan tidak ditemukan', 404);
    if (order.workStatus === 'CANCELLED') {
      throw new AppError('Pesanan sudah dibatalkan, tidak bisa menerima pembayaran', 409);
    }

    const remaining = order.total - order.paidAmount;
    if (remaining <= 0) throw new AppError('Pesanan sudah lunas', 409);
    if (body.amount > remaining) {
      throw new AppError(`Nominal melebihi sisa tagihan (Rp ${remaining})`, 400);
    }

    const newPaid = order.paidAmount + body.amount;
    const newStatus = derivePaymentStatus(newPaid, order.total);

    // Kunci optimistis: hanya berhasil jika paidAmount belum berubah sejak dibaca
    const updated = await tx.order.updateMany({
      where: { id, paidAmount: order.paidAmount },
      data: { paidAmount: newPaid, paymentStatus: newStatus },
    });
    if (updated.count === 0) {
      throw new AppError('Data pembayaran baru saja berubah, silakan coba lagi', 409);
    }

    const payment = await tx.payment.create({
      data: {
        orderId: id,
        amount: body.amount,
        method: body.method,
        note: body.note,
        receivedById: req.user.id,
      },
    });

    return {
      payment,
      order: {
        id,
        total: order.total,
        paidAmount: newPaid,
        remaining: order.total - newPaid,
        paymentStatus: newStatus,
      },
    };
  });

  res.status(201).json({ data: result });
}

// ---------- Riwayat pembayaran ----------
async function list(req, res) {
  const { id } = idParam.parse(req.params);

  const order = await prisma.order.findFirst({
    where: { id, ...outletScope(req.scope) },
    select: { id: true, orderNumber: true, total: true, paidAmount: true, paymentStatus: true },
  });
  if (!order) throw new AppError('Pesanan tidak ditemukan', 404);

  const payments = await prisma.payment.findMany({
    where: { orderId: id },
    orderBy: { id: 'asc' },
    include: { receivedBy: { select: { id: true, name: true } } },
  });

  res.json({
    data: { order: { ...order, remaining: order.total - order.paidAmount }, payments },
  });
}

module.exports = { create, list };