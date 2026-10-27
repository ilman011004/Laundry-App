const prisma = require('../lib/prisma');

// Kas tiap pengguna: tunai yang diterima dikurangi setoran
async function perUser() {
  const [paid, dep, users] = await Promise.all([
    prisma.payment.groupBy({
      by: ['receivedById'],
      where: { method: 'CASH' },
      _sum: { amount: true },
    }),
    prisma.cashDeposit.groupBy({ by: ['cashierId'], _sum: { amount: true } }),
    prisma.user.findMany({
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

// Kas yang dipegang satu pengguna (db bisa prisma atau transaksi)
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

async function cashSummary(user) {
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

  const [rows, expenses, confirmed, pending] = await Promise.all([
    perUser(),
    prisma.expense.aggregate({ _sum: { amount: true } }),
    prisma.cashDeposit.aggregate({
      where: { status: 'CONFIRMED' },
      _sum: { amount: true },
    }),
    prisma.cashDeposit.aggregate({
      where: { status: 'PENDING' },
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