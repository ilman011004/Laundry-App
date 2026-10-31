const prisma = require('../lib/prisma');
const { cashSummary } = require('../services/cash.service');
const { outletScope } = require('../middleware/scope');
const t = require('../utils/time');

const sum = (r) => r._sum.amount || 0;

async function summary(req, res) {
  const { isOwner, timezone: tz } = req.scope;
  const sc = outletScope(req.scope);
  const now = new Date();
  const dayStart = t.startOfDay(now, tz);
  const monthStart = t.startOfMonth(now, tz);

  const overdueWhere = {
    ...sc,
    workStatus: { in: ['RECEIVED', 'WASHING', 'DRYING', 'IRONING'] },
    estimatedDoneAt: { lt: now },
  };
  const unpaidWhere = { ...sc, workStatus: { not: 'CANCELLED' }, paymentStatus: { not: 'PAID' } };

  const [byStatus, completedToday, ordersToday, unpaid, overdue, overdueList, topDebts, cash] =
    await Promise.all([
      prisma.order.groupBy({ by: ['workStatus'], where: sc, _count: { _all: true } }),
      prisma.order.count({
        where: { ...sc, workStatus: 'COMPLETED', completedAt: { gte: dayStart } },
      }),
      prisma.order.count({
        where: { ...sc, createdAt: { gte: dayStart }, workStatus: { not: 'CANCELLED' } },
      }),
      prisma.order.aggregate({
        where: unpaidWhere,
        _count: { _all: true },
        _sum: { total: true, paidAmount: true },
      }),
      prisma.order.count({ where: overdueWhere }),
      prisma.order.findMany({
        where: overdueWhere,
        orderBy: { estimatedDoneAt: 'asc' },
        take: 5,
        select: {
          id: true,
          orderNumber: true,
          workStatus: true,
          estimatedDoneAt: true,
          customer: { select: { name: true } },
        },
      }),
      prisma.order.findMany({
        where: unpaidWhere,
        select: {
          id: true,
          orderNumber: true,
          total: true,
          paidAmount: true,
          customer: { select: { name: true } },
        },
        orderBy: { createdAt: 'asc' },
        take: 50,
      }),
      cashSummary(req.user, req.scope),
    ]);

  const count = (s) => byStatus.find((x) => x.workStatus === s)?._count._all || 0;

  const data = {
    orders: {
      inProgress: count('RECEIVED') + count('WASHING') + count('DRYING') + count('IRONING'),
      ready: count('READY'),
      completedToday,
      today: ordersToday,
      overdue,
      overdueList: overdueList.map((o) => ({
        id: o.id,
        orderNumber: o.orderNumber,
        customerName: o.customer.name,
        workStatus: o.workStatus,
        estimatedDoneAt: o.estimatedDoneAt,
      })),
    },
    payments: {
      unpaidCount: unpaid._count._all,
      outstanding: (unpaid._sum.total || 0) - (unpaid._sum.paidAmount || 0),
      topDebts: topDebts
        .map((o) => ({
          id: o.id,
          orderNumber: o.orderNumber,
          customerName: o.customer.name,
          remaining: o.total - o.paidAmount,
        }))
        .sort((a, b) => b.remaining - a.remaining)
        .slice(0, 3),
    },
    cash,
  };

  // Omzet dan uang masuk hanya untuk Pemilik.
  // transfer dan qris sengaja kumulatif (saldo non-tunai), sama seperti kas.
  if (isOwner) {
    const paid = { order: sc };
    const [transfer, qris, incToday, incMonth, expMonth] = await Promise.all([
      prisma.payment.aggregate({ where: { ...paid, method: 'TRANSFER' }, _sum: { amount: true } }),
      prisma.payment.aggregate({ where: { ...paid, method: 'QRIS' }, _sum: { amount: true } }),
      prisma.payment.aggregate({
        where: { ...paid, paidAt: { gte: dayStart } },
        _sum: { amount: true },
      }),
      prisma.payment.aggregate({
        where: { ...paid, paidAt: { gte: monthStart } },
        _sum: { amount: true },
      }),
      prisma.expense.aggregate({
        where: { ...sc, spentAt: { gte: monthStart } },
        _sum: { amount: true },
      }),
    ]);

    data.money = {
      transfer: sum(transfer),
      qris: sum(qris),
      incomeToday: sum(incToday),
      incomeMonth: sum(incMonth),
      expensesMonth: sum(expMonth),
    };
  }

  res.json({ data });
}

module.exports = { summary };