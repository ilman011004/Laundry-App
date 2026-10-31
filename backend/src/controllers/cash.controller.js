const { z } = require('zod');
const prisma = require('../lib/prisma');
const { AppError } = require('../middleware/errorHandler');
const { outletScope } = require('../middleware/scope');
const { cashSummary, heldBy } = require('../services/cash.service');

const idParam = z.object({ id: z.coerce.number().int().positive() });

const depositSchema = z.object({
  amount: z.number().int().positive('Nominal harus lebih dari 0'),
  note: z.string().trim().max(200).optional(),
});

function format(d) {
  return {
    id: d.id,
    cashierName: d.cashier.name,
    amount: d.amount,
    note: d.note,
    status: d.status,
    createdAt: d.createdAt,
    confirmedAt: d.confirmedAt,
  };
}

async function overview(req, res) {
  const { isOwner } = req.scope;
  const [summary, deposits] = await Promise.all([
    cashSummary(req.user, req.scope),
    prisma.cashDeposit.findMany({
      where: isOwner ? outletScope(req.scope) : { cashierId: req.user.id },
      orderBy: { id: 'desc' },
      take: 50,
      include: { cashier: { select: { name: true } } },
    }),
  ]);
  res.json({ data: { summary, deposits: deposits.map(format) } });
}

// Hanya kasir; outlet dan usaha diambil dari akun kasir itu sendiri
async function createDeposit(req, res) {
  const body = depositSchema.parse(req.body);
  const { businessId, outletId } = req.scope;

  const dep = await prisma.$transaction(async (tx) => {
    const held = await heldBy(tx, req.user.id);
    if (body.amount > held) {
      throw new AppError(`Melebihi kas yang Anda pegang (Rp ${held})`, 400);
    }
    return tx.cashDeposit.create({
      data: {
        businessId,
        outletId,
        cashierId: req.user.id,
        amount: body.amount,
        note: body.note || null,
      },
      include: { cashier: { select: { name: true } } },
    });
  });

  res.status(201).json({ data: format(dep) });
}

async function confirmDeposit(req, res) {
  const { id } = idParam.parse(req.params);

  const changed = await prisma.cashDeposit.updateMany({
    where: { id, status: 'PENDING', ...outletScope(req.scope) },
    data: { status: 'CONFIRMED', confirmedAt: new Date(), confirmedById: req.user.id },
  });
  if (changed.count === 0) {
    throw new AppError('Setoran tidak ditemukan atau sudah dikonfirmasi', 409);
  }
  res.json({ message: 'Setoran diterima' });
}

module.exports = { overview, createDeposit, confirmDeposit };