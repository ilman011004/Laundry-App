const { z } = require('zod');
const prisma = require('../lib/prisma');
const { AppError } = require('../middleware/errorHandler');
const t = require('../utils/time');

const idParam = z.object({ id: z.coerce.number().int().positive() });
const dateRe = /^\d{4}-\d{2}-\d{2}$/;
const DAY = 24 * 3600 * 1000;

const baseSchema = z.object({
  category: z.string().trim().min(2, 'Kategori minimal 2 karakter').max(50),
  description: z.string().trim().max(200).optional(),
  amount: z.number().int().positive('Nominal harus lebih dari 0').max(1_000_000_000),
  spentAt: z.coerce
    .date()
    .refine((d) => d.getTime() <= Date.now() + DAY, 'Tanggal pengeluaran tidak boleh di masa depan')
    .optional(),
});

const createSchema = baseSchema;
const updateSchema = baseSchema
  .partial()
  .refine((o) => Object.keys(o).length > 0, 'Tidak ada data yang diubah');

const listQuery = z.object({
  from: z.string().regex(dateRe, 'Format tanggal harus YYYY-MM-DD').optional(),
  to: z.string().regex(dateRe, 'Format tanggal harus YYYY-MM-DD').optional(),
  category: z.string().trim().optional(),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
});

// Ubah "YYYY-MM-DD" (tanggal lokal) menjadi rentang [start, end)
function dayRange(from, to) {
  const start = from ? t.parseLocalDate(from) : null;
  const end = to ? t.addDays(t.parseLocalDate(to), 1) : null;

  if (from && t.dayKey(start) !== from) throw new AppError('Tanggal awal tidak valid', 400);
  if (to && t.dayKey(t.addDays(end, -1)) !== to) throw new AppError('Tanggal akhir tidak valid', 400);
  if (start && end && end <= start) {
    throw new AppError('Tanggal akhir tidak boleh sebelum tanggal awal', 400);
  }
  return { start, end };
}

const withCreator = { createdBy: { select: { id: true, name: true } } };

// ---------- Catat pengeluaran ----------
async function create(req, res) {
  const body = createSchema.parse(req.body);

  const expense = await prisma.expense.create({
    data: {
      category: body.category,
      description: body.description,
      amount: body.amount,
      ...(body.spentAt ? { spentAt: body.spentAt } : {}),
      createdById: req.user.id,
    },
    include: withCreator,
  });

  res.status(201).json({ data: expense });
}

// ---------- Daftar ----------
async function list(req, res) {
  const q = listQuery.parse(req.query);
  const { start, end } = dayRange(q.from, q.to);

  const where = {};
  if (q.category) where.category = { equals: q.category, mode: 'insensitive' };
  if (start || end) {
    where.spentAt = {};
    if (start) where.spentAt.gte = start;
    if (end) where.spentAt.lt = end;
  }

  const [total, sum, data] = await Promise.all([
    prisma.expense.count({ where }),
    prisma.expense.aggregate({ where, _sum: { amount: true } }),
    prisma.expense.findMany({
      where,
      orderBy: [{ spentAt: 'desc' }, { id: 'desc' }],
      skip: (q.page - 1) * q.limit,
      take: q.limit,
      include: withCreator,
    }),
  ]);

  res.json({
    data,
    meta: {
      page: q.page,
      limit: q.limit,
      total,
      totalPages: Math.ceil(total / q.limit),
      totalAmount: sum._sum.amount || 0,
    },
  });
}

// ---------- Daftar kategori yang pernah dipakai ----------
async function categories(req, res) {
  const rows = await prisma.expense.findMany({
    distinct: ['category'],
    select: { category: true },
    orderBy: { category: 'asc' },
  });
  res.json({ data: rows.map((r) => r.category) });
}

// ---------- Ubah ----------
async function update(req, res) {
  const { id } = idParam.parse(req.params);
  const body = updateSchema.parse(req.body);

  const exists = await prisma.expense.findUnique({ where: { id }, select: { id: true } });
  if (!exists) throw new AppError('Pengeluaran tidak ditemukan', 404);

  const expense = await prisma.expense.update({
    where: { id },
    data: body,
    include: withCreator,
  });
  res.json({ data: expense });
}

// ---------- Hapus ----------
async function remove(req, res) {
  const { id } = idParam.parse(req.params);

  const exists = await prisma.expense.findUnique({ where: { id }, select: { id: true } });
  if (!exists) throw new AppError('Pengeluaran tidak ditemukan', 404);

  await prisma.expense.delete({ where: { id } });
  res.json({ data: { id, deleted: true } });
}

module.exports = { create, list, categories, update, remove };