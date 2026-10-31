const bcrypt = require('bcryptjs');
const { z } = require('zod');
const prisma = require('../lib/prisma');
const { AppError } = require('../middleware/errorHandler');

const idParam = z.object({ id: z.coerce.number().int().positive() });

const createSchema = z.object({
  name: z.string().trim().min(1, 'Nama wajib diisi'),
  username: z
    .string()
    .trim()
    .toLowerCase()
    .min(3, 'Username minimal 3 karakter')
    .regex(/^[a-z0-9._]+$/, 'Username hanya huruf kecil, angka, titik, underscore'),
  password: z.string().min(8, 'Password minimal 8 karakter'),
  role: z.enum(['CASHIER', 'OPERATOR']),
  outletId: z.number().int().positive('Outlet wajib dipilih'),
});

const updateSchema = z.object({
  name: z.string().trim().min(1).optional(),
  role: z.enum(['CASHIER', 'OPERATOR']).optional(),
  isActive: z.boolean().optional(),
  outletId: z.number().int().positive().optional(),
});

const resetPasswordSchema = z.object({
  newPassword: z.string().min(8, 'Password minimal 8 karakter'),
});

// Field yang boleh dikirim ke klien (tanpa passwordHash)
const userSelect = {
  id: true,
  name: true,
  username: true,
  email: true,
  isActive: true,
  createdAt: true,
  outletId: true,
  role: { select: { name: true } },
  outlet: { select: { name: true } },
};

function format(u) {
  return {
    id: u.id,
    name: u.name,
    username: u.username,
    email: u.email,
    role: u.role.name,
    isActive: u.isActive,
    createdAt: u.createdAt,
    outletId: u.outletId,
    outletName: u.outlet ? u.outlet.name : null,
  };
}

// Outlet harus milik usaha pemilik yang sedang login dan masih aktif
async function assertOwnOutlet(businessId, outletId) {
  const outlet = await prisma.outlet.findFirst({
    where: { id: outletId, businessId, isActive: true },
    select: { id: true },
  });
  if (!outlet) throw new AppError('Outlet tidak ditemukan atau tidak aktif', 400);
}

async function list(req, res) {
  const users = await prisma.user.findMany({
    where: { businessId: req.user.businessId },
    select: userSelect,
    orderBy: { id: 'asc' },
  });
  res.json({ data: users.map(format) });
}

async function create(req, res) {
  const body = createSchema.parse(req.body);
  const businessId = req.user.businessId;

  await assertOwnOutlet(businessId, body.outletId);

  const role = await prisma.role.findUnique({ where: { name: body.role } });
  if (!role) throw new AppError('Role tidak ditemukan', 400);

  let user;
  try {
    user = await prisma.user.create({
      data: {
        name: body.name,
        username: body.username,
        passwordHash: await bcrypt.hash(body.password, 12),
        roleId: role.id,
        businessId,
        outletId: body.outletId,
      },
      select: userSelect,
    });
  } catch (e) {
    if (e.code === 'P2002') throw new AppError('Username sudah dipakai', 409);
    throw e;
  }

  res.status(201).json({ data: format(user) });
}

async function update(req, res) {
  const { id } = idParam.parse(req.params);
  const body = updateSchema.parse(req.body);

  const target = await prisma.user.findFirst({
    where: { id, businessId: req.user.businessId },
    include: { role: true },
  });
  if (!target) throw new AppError('Pengguna tidak ditemukan', 404);

  // Akun OWNER tidak boleh diubah role/statusnya lewat endpoint ini
  if (
    target.role.name === 'OWNER' &&
    (body.role || body.isActive === false || body.outletId)
  ) {
    throw new AppError('Akun pemilik tidak bisa dinonaktifkan atau diubah', 400);
  }

  const data = {};
  if (body.name !== undefined) data.name = body.name;
  if (body.isActive !== undefined) data.isActive = body.isActive;
  if (body.outletId !== undefined) {
    await assertOwnOutlet(req.user.businessId, body.outletId);
    data.outletId = body.outletId;
  }
  if (body.role) {
    const role = await prisma.role.findUnique({ where: { name: body.role } });
    data.roleId = role.id;
  }

  const user = await prisma.user.update({
    where: { id },
    data,
    select: userSelect,
  });

  res.json({ data: format(user) });
}

async function resetPassword(req, res) {
  const { id } = idParam.parse(req.params);
  const { newPassword } = resetPasswordSchema.parse(req.body);

  const exists = await prisma.user.findFirst({
    where: { id, businessId: req.user.businessId },
    select: { id: true },
  });
  if (!exists) throw new AppError('Pengguna tidak ditemukan', 404);

  await prisma.user.update({
    where: { id },
    data: { passwordHash: await bcrypt.hash(newPassword, 12) },
  });

  res.json({ message: 'Password berhasil direset' });
}

module.exports = { list, create, update, resetPassword };