const { z } = require('zod');
const prisma = require('../lib/prisma');
const { AppError } = require('../middleware/errorHandler');

const idParam = z.object({ id: z.coerce.number().int().positive() });

// Urutan alur pengerjaan (tahap boleh dilewati, tidak boleh mundur)
const FLOW = ['RECEIVED', 'WASHING', 'DRYING', 'IRONING', 'READY', 'COMPLETED'];

const statusSchema = z.object({
  status: z.enum(['WASHING', 'DRYING', 'IRONING', 'READY', 'COMPLETED']),
  note: z.string().trim().max(200).optional(),
});

const cancelSchema = z.object({
  note: z.string().trim().min(3, 'Alasan pembatalan wajib diisi').max(200),
});

const orderSummary = {
  id: true,
  orderNumber: true,
  workStatus: true,
  paymentStatus: true,
  total: true,
  paidAmount: true,
  completedAt: true,
};

// ---------- Ubah status ----------
async function update(req, res) {
  const { id } = idParam.parse(req.params);
  const body = statusSchema.parse(req.body);

  const order = await prisma.$transaction(async (tx) => {
    const current = await tx.order.findUnique({
      where: { id },
      select: { workStatus: true },
    });
    if (!current) throw new AppError('Pesanan tidak ditemukan', 404);

    const from = current.workStatus;
    const to = body.status;

    if (from === 'CANCELLED') throw new AppError('Pesanan sudah dibatalkan', 409);
    if (from === 'COMPLETED') throw new AppError('Pesanan sudah selesai diserahkan', 409);

    if (FLOW.indexOf(to) <= FLOW.indexOf(from)) {
      throw new AppError(`Status tidak bisa mundur atau tetap (${from} → ${to})`, 409);
    }
    if (to === 'COMPLETED' && from !== 'READY') {
      throw new AppError('Pesanan harus berstatus READY sebelum diserahkan', 409);
    }

    // Jaga dari perubahan bersamaan oleh dua orang
    const changed = await tx.order.updateMany({
      where: { id, workStatus: from },
      data: {
        workStatus: to,
        ...(to === 'COMPLETED' ? { completedAt: new Date() } : {}),
      },
    });
    if (changed.count === 0) {
      throw new AppError('Status pesanan baru saja berubah, muat ulang lalu coba lagi', 409);
    }

    await tx.orderStatusHistory.create({
      data: {
        orderId: id,
        fromStatus: from,
        toStatus: to,
        changedById: req.user.id,
        note: body.note || null,
      },
    });

    return tx.order.findUnique({ where: { id }, select: orderSummary });
  });

  const remaining = order.total - order.paidAmount;
  const data = { ...order, remaining };
  if (order.workStatus === 'COMPLETED' && remaining > 0) {
    data.warning = `Pesanan diserahkan dengan sisa tagihan Rp ${remaining}`;
  }

  res.json({ data });
}

// ---------- Batalkan pesanan (OWNER) ----------
async function cancel(req, res) {
  const { id } = idParam.parse(req.params);
  const body = cancelSchema.parse(req.body);

  const order = await prisma.$transaction(async (tx) => {
    const current = await tx.order.findUnique({
      where: { id },
      select: { workStatus: true, paidAmount: true },
    });
    if (!current) throw new AppError('Pesanan tidak ditemukan', 404);

    if (current.workStatus === 'CANCELLED') throw new AppError('Pesanan sudah dibatalkan', 409);
    if (current.workStatus === 'COMPLETED') {
      throw new AppError('Pesanan yang sudah diserahkan tidak bisa dibatalkan', 409);
    }
    if (current.paidAmount > 0) {
      throw new AppError(
        'Pesanan sudah memiliki pembayaran. Fitur refund belum tersedia, jadi pembatalan ditolak',
        409
      );
    }

    const changed = await tx.order.updateMany({
      where: { id, workStatus: current.workStatus },
      data: { workStatus: 'CANCELLED' },
    });
    if (changed.count === 0) {
      throw new AppError('Status pesanan baru saja berubah, muat ulang lalu coba lagi', 409);
    }

    await tx.orderStatusHistory.create({
      data: {
        orderId: id,
        fromStatus: current.workStatus,
        toStatus: 'CANCELLED',
        changedById: req.user.id,
        note: body.note,
      },
    });

    return tx.order.findUnique({ where: { id }, select: orderSummary });
  });

  res.json({ data: { ...order, remaining: order.total - order.paidAmount } });
}

module.exports = { update, cancel };