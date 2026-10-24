const { z } = require('zod');
const prisma = require('../lib/prisma');
const { AppError } = require('../middleware/errorHandler');
const t = require('../utils/time');

const ACTIVE = ['RECEIVED', 'WASHING', 'DRYING', 'IRONING'];
const notCancelled = { workStatus: { not: 'CANCELLED' } };
const MAX_DAYS = 93;

function emptyMethods() {
  return { CASH: 0, TRANSFER: 0, QRIS: 0 };
}

// Angka ringkas untuk satu periode [from, to)
async function periodFigures(from, to) {
  const [orders, cash, spent] = await Promise.all([
    prisma.order.aggregate({
      where: { ...notCancelled, createdAt: { gte: from, lt: to } },
      _count: { _all: true },
      _sum: { total: true },
    }),
    prisma.payment.aggregate({
      where: { paidAt: { gte: from, lt: to } },
      _sum: { amount: true },
    }),
    prisma.expense.aggregate({
      where: { spentAt: { gte: from, lt: to } },
      _sum: { amount: true },
    }),
  ]);

  const cashIn = cash._sum.amount || 0;
  const expenses = spent._sum.amount || 0;

  return {
    orderCount: orders._count._all,
    sales: orders._sum.total || 0,
    cashIn,
    expenses,
    netCash: cashIn - expenses,
  };
}

// ---------- Dashboard ----------
async function dashboard(req, res) {
  const now = new Date();
  const todayStart = t.startOfDay(now);
  const tomorrowStart = t.addDays(todayStart, 1);
  const monthStart = t.startOfMonth(now);
  const nextMonthStart = t.startOfNextMonth(now);

  const [today, month, inProcess, ready, late, receivable, byMethod] = await Promise.all([
    periodFigures(todayStart, tomorrowStart),
    periodFigures(monthStart, nextMonthStart),
    prisma.order.count({ where: { workStatus: { in: ACTIVE } } }),
    prisma.order.count({ where: { workStatus: 'READY' } }),
    prisma.order.count({ where: { workStatus: { in: ACTIVE }, estimatedDoneAt: { lt: now } } }),
    prisma.order.aggregate({
      where: { ...notCancelled, paymentStatus: { in: ['UNPAID', 'PARTIAL'] } },
      _count: { _all: true },
      _sum: { total: true, paidAmount: true },
    }),
    prisma.payment.groupBy({
      by: ['method'],
      where: { paidAt: { gte: todayStart, lt: tomorrowStart } },
      _sum: { amount: true },
    }),
  ]);

  const cashByMethod = emptyMethods();
  for (const row of byMethod) cashByMethod[row.method] = row._sum.amount || 0;

  res.json({
    data: {
      generatedAt: now.toISOString(),
      today: { date: t.dayKey(now), ...today, cashByMethod },
      month: { month: t.dayKey(monthStart).slice(0, 7), ...month },
      queue: { inProcess, ready, late },
      receivables: {
        orderCount: receivable._count._all,
        amount: (receivable._sum.total || 0) - (receivable._sum.paidAmount || 0),
      },
    },
  });
}

// ---------- Rekap per periode ----------
const dateRe = /^\d{4}-\d{2}-\d{2}$/;
const summaryQuery = z.object({
  from: z.string().regex(dateRe, 'Format tanggal harus YYYY-MM-DD'),
  to: z.string().regex(dateRe, 'Format tanggal harus YYYY-MM-DD'),
});

async function summary(req, res) {
  const q = summaryQuery.parse(req.query);

  const from = t.parseLocalDate(q.from);
  const toExclusive = t.addDays(t.parseLocalDate(q.to), 1);

  // Tolak tanggal yang tidak ada di kalender (mis. 2026-02-31)
  if (t.dayKey(from) !== q.from || t.dayKey(t.addDays(toExclusive, -1)) !== q.to) {
    throw new AppError('Tanggal tidak valid', 400);
  }

  const days = Math.round((toExclusive - from) / (24 * 3600 * 1000));
  if (days <= 0) throw new AppError('Tanggal akhir tidak boleh sebelum tanggal awal', 400);
  if (days > MAX_DAYS) throw new AppError(`Rentang maksimal ${MAX_DAYS} hari`, 400);

  const [orders, payments, expenses, topServices] = await Promise.all([
    prisma.order.findMany({
      where: { ...notCancelled, createdAt: { gte: from, lt: toExclusive } },
      select: { createdAt: true, total: true },
    }),
    prisma.payment.findMany({
      where: { paidAt: { gte: from, lt: toExclusive } },
      select: { paidAt: true, amount: true, method: true },
    }),
    prisma.expense.findMany({
      where: { spentAt: { gte: from, lt: toExclusive } },
      select: { spentAt: true, amount: true, category: true },
    }),
    prisma.orderItem.groupBy({
      by: ['serviceName'],
      where: { order: { ...notCancelled, createdAt: { gte: from, lt: toExclusive } } },
      _sum: { lineTotal: true, quantity: true },
      _count: { _all: true },
      orderBy: { _sum: { lineTotal: 'desc' } },
      take: 5,
    }),
  ]);

  // Siapkan semua tanggal (termasuk yang kosong) agar grafik tidak bolong
  const rows = new Map();
  for (let i = 0; i < days; i++) {
    const key = t.dayKey(t.addDays(from, i));
    rows.set(key, { date: key, orderCount: 0, sales: 0, cashIn: 0, expenses: 0 });
  }

  for (const o of orders) {
    const r = rows.get(t.dayKey(o.createdAt));
    r.orderCount += 1;
    r.sales += o.total;
  }

  const cashByMethod = emptyMethods();
  for (const p of payments) {
    rows.get(t.dayKey(p.paidAt)).cashIn += p.amount;
    cashByMethod[p.method] += p.amount;
  }

  const expenseByCategory = {};
  for (const e of expenses) {
    rows.get(t.dayKey(e.spentAt)).expenses += e.amount;
    expenseByCategory[e.category] = (expenseByCategory[e.category] || 0) + e.amount;
  }

  const daily = [...rows.values()].map((r) => ({ ...r, netCash: r.cashIn - r.expenses }));

  const totals = daily.reduce(
    (s, r) => ({
      orderCount: s.orderCount + r.orderCount,
      sales: s.sales + r.sales,
      cashIn: s.cashIn + r.cashIn,
      expenses: s.expenses + r.expenses,
    }),
    { orderCount: 0, sales: 0, cashIn: 0, expenses: 0 }
  );
  totals.netCash = totals.cashIn - totals.expenses;

  res.json({
    data: {
      period: { from: q.from, to: q.to, days },
      totals,
      cashByMethod,
      expenseByCategory,
      topServices: topServices.map((s) => ({
        serviceName: s.serviceName,
        orderCount: s._count._all,
        quantity: Number(s._sum.quantity ?? 0),
        revenue: s._sum.lineTotal || 0,
      })),
      daily,
    },
  });
}

module.exports = { dashboard, summary };