const prisma = require('../lib/prisma');
const { cashSummary } = require('../services/cash.service');

const HOUR = 3600 * 1000;
const TZ = 8; // Asia/Makassar

function startOfDayLocal(now = new Date()) {
  const l = new Date(now.getTime() + TZ * HOUR);
  return new Date(Date.UTC(l.getUTCFullYear(), l.getUTCMonth(), l.getUTCDate()) - TZ * HOUR);
}

function startOfMonthLocal(now = new Date()) {
  const l = new Date(now.getTime() + TZ * HOUR);
  return new Date(Date.UTC(l.getUTCFullYear(), l.getUTCMonth(), 1) - TZ * HOUR);
}

const sum = (r) => r._sum.amount || 0;

async function summary(req, res) {
  const isOwner = req.user.role === 'OWNER';
  const now = new Date();
  const dayStart = startOfDayLocal(now);
  const monthStart = startOfMonthLocal(now);

  const overdueWhere = {
    workStatus: { in: ['RECEIVED', 'WASHING', 'DRYING', 'IRONING'] },
    estimatedDoneAt: { lt: now },
  };

  const [byStatus, completedToday, ordersToday, unpaid, overdue, overdueList, topDebts, cash] =
    await Promise.all([
      prisma.order.groupBy({ by: ['workStatus'], _count: { _all: true } }),
      prisma.order.count({
        where: { workStatus: 'COMPLETED', completedAt: { gte: dayStart } },
      }),
      prisma.order.count({
        where: { createdAt: { gte: dayStart }, workStatus: { not: 'CANCELLED' } },
      }),
      prisma.order.aggregate({
        where: { workStatus: { not: 'CANCELLED' }, paymentStatus: { not: 'PAID' } },
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
        where: { workStatus: { not: 'CANCELLED' }, paymentStatus: { not: 'PAID' } },
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
      cashSummary(req.user),
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

  // Omzet dan uang masuk hanya untuk Pemilik
  if (isOwner) {
    const [transfer, qris, incToday, incMonth, expMonth] = await Promise.all([
      prisma.payment.aggregate({ where: { method: 'TRANSFER' }, _sum: { amount: true } }),
      prisma.payment.aggregate({ where: { method: 'QRIS' }, _sum: { amount: true } }),
      prisma.payment.aggregate({ where: { paidAt: { gte: dayStart } }, _sum: { amount: true } }),
      prisma.payment.aggregate({ where: { paidAt: { gte: monthStart } }, _sum: { amount: true } }),
      prisma.expense.aggregate({ where: { spentAt: { gte: monthStart } }, _sum: { amount: true } }),
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