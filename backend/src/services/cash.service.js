const prisma = require('../lib/prisma');
const { outletScope } = require('../middleware/scope');

// Kas tiap pengguna dalam lingkup (usaha, dan outlet bila dipilih):
// tunai yang diterima dikurangi setoran
async function perUser(scope) {
  const sc = outletScope(scope);

  const [paid, dep, users] = await Promise.all([
    prisma.payment.groupBy({
      by: ['receivedById'],
      where: { method: 'CASH', order: sc },
      _sum: { amount: true },
    }),
    prisma.cashDeposit.groupBy({ by: ['cashierId'], where: sc, _sum: { amount: true } }),
    prisma.user.findMany({
      where: {
        businessId: scope.businessId,
        // Bila satu outlet dipilih: kasir outlet itu dan akun pemilik
        ...(scope.outletId
          ? { OR: [{ outletId: scope.outletId }, { role: { name: 'OWNER' } }] }
          : {}),
      },
      select: { id: true, name: true, isActive: true, role: { select: { name: true } } },
    }),
  ]);

  const received = new Map(paid.map((p) => [p.receivedById, p._sum.amount || 0]));
  const deposited = new Map(dep.map((d) => [d.cashierId, d._sum.amount || 0]));

  return users.map((u) => {
    const r = received.get(u.id) || 0;
    const d = deposited.get(u.id) || 0;
    return {
      id: u.id,
      name: u.name,
      role: u.role.name,
      isActive: u.isActive,
      received: r,
      held: r - d,
    };
  });
}

// Kas yang dipegang satu pengguna (db bisa prisma atau transaksi).
// Aman tanpa filter usaha karena userId selalu berasal dari token.
async function heldBy(db, userId) {
  const [paid, dep] = await Promise.all([
    db.payment.aggregate({
      where: { method: 'CASH', receivedById: userId },
      _sum: { amount: true },
    }),
    db.cashDeposit.aggregate({ where: { cashierId: userId }, _sum: { amount: true } }),
  ]);
  return (paid._sum.amount || 0) - (dep._sum.amount || 0);
}

async function cashSummary(user, scope) {
  if (user.role !== 'OWNER') {
    const [held, pending] = await Promise.all([
      heldBy(prisma, user.id),
      prisma.cashDeposit.aggregate({
        where: { cashierId: user.id, status: 'PENDING' },
        _sum: { amount: true },
      }),
    ]);
    return { held, pendingDeposits: pending._sum.amount || 0 };
  }

  const sc = outletScope(scope);

  const [rows, expenses, confirmed, pending] = await Promise.all([
    perUser(scope),
    prisma.expense.aggregate({ where: sc, _sum: { amount: true } }),
    prisma.cashDeposit.aggregate({
      where: { ...sc, status: 'CONFIRMED' },
      _sum: { amount: true },
    }),
    prisma.cashDeposit.aggregate({
      where: { ...sc, status: 'PENDING' },
      _sum: { amount: true },
      _count: { _all: true },
    }),
  ]);

  const ownerReceived = rows
    .filter((r) => r.role === 'OWNER')
    .reduce((s, r) => s + r.received, 0);
  const cashiers = rows
    .filter((r) => r.role !== 'OWNER' && (r.isActive || r.held !== 0))
    .map((r) => ({ id: r.id, name: r.name, held: r.held }));

  const ownerCash = ownerReceived + (confirmed._sum.amount || 0) - (expenses._sum.amount || 0);
  const cashierHeldTotal = cashiers.reduce((s, c) => s + c.held, 0);
  const pendingTotal = pending._sum.amount || 0;

  return {
    total: ownerCash + cashierHeldTotal + pendingTotal,
    ownerCash,
    cashierHeldTotal,
    pendingTotal,
    pendingCount: pending._count._all,
    cashiers,
  };
}

module.exports = { cashSummary, heldBy };