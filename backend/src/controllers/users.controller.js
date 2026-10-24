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
});

const updateSchema = z.object({
  name: z.string().trim().min(1).optional(),
  role: z.enum(['CASHIER', 'OPERATOR']).optional(),
  isActive: z.boolean().optional(),
});

const resetPasswordSchema = z.object({
  newPassword: z.string().min(8, 'Password minimal 8 karakter'),
});

// Field yang boleh dikirim ke klien (tanpa passwordHash)
const userSelect = {
  id: true,
  name: true,
  username: true,
  isActive: true,
  createdAt: true,
  role: { select: { name: true } },
};

function format(u) {
  return {
    id: u.id,
    name: u.name,
    username: u.username,
    role: u.role.name,
    isActive: u.isActive,
    createdAt: u.createdAt,
  };
}

async function list(req, res) {
  const users = await prisma.user.findMany({
    select: userSelect,
    orderBy: { id: 'asc' },
  });
  res.json({ data: users.map(format) });
}

async function create(req, res) {
  const body = createSchema.parse(req.body);

  const role = await prisma.role.findUnique({ where: { name: body.role } });
  if (!role) throw new AppError('Role tidak ditemukan', 400);

  const user = await prisma.user.create({
    data: {
      name: body.name,
      username: body.username,
      passwordHash: await bcrypt.hash(body.password, 12),
      roleId: role.id,
    },
    select: userSelect,
  });

  res.status(201).json({ data: format(user) });
}

async function update(req, res) {
  const { id } = idParam.parse(req.params);
  const body = updateSchema.parse(req.body);

  const target = await prisma.user.findUnique({
    where: { id },
    include: { role: true },
  });
  if (!target) throw new AppError('Pengguna tidak ditemukan', 404);

  // Akun OWNER tidak boleh diubah role/statusnya lewat endpoint ini
  if (target.role.name === 'OWNER' && (body.role || body.isActive === false)) {
    throw new AppError('Akun pemilik tidak bisa dinonaktifkan atau diubah rolenya', 400);
  }

  const data = {};
  if (body.name !== undefined) data.name = body.name;
  if (body.isActive !== undefined) data.isActive = body.isActive;
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

  const exists = await prisma.user.findUnique({ where: { id } });
  if (!exists) throw new AppError('Pengguna tidak ditemukan', 404);

  await prisma.user.update({
    where: { id },
    data: { passwordHash: await bcrypt.hash(newPassword, 12) },
  });

  res.json({ message: 'Password berhasil direset' });
}

module.exports = { list, create, update, resetPassword };