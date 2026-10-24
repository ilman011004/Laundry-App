const bcrypt = require('bcryptjs');
const { z } = require('zod');
const prisma = require('../lib/prisma');
const { AppError } = require('../middleware/errorHandler');
const {
  signAccessToken,
  signRefreshToken,
  verifyRefreshToken,
} = require('../utils/jwt');

const loginSchema = z.object({
  username: z.string().trim().min(1, 'Username wajib diisi'),
  password: z.string().min(1, 'Password wajib diisi'),
});

const refreshSchema = z.object({
  refreshToken: z.string().min(1),
});

const changePasswordSchema = z.object({
  oldPassword: z.string().min(1),
  newPassword: z.string().min(8, 'Password baru minimal 8 karakter'),
});

function publicUser(user) {
  return {
    id: user.id,
    name: user.name,
    username: user.username,
    role: user.role.name,
  };
}

async function login(req, res) {
  const { username, password } = loginSchema.parse(req.body);

  const user = await prisma.user.findUnique({
    where: { username },
    include: { role: true },
  });

  // Pesan sama untuk username salah / password salah (tidak membocorkan info)
  const valid = user && (await bcrypt.compare(password, user.passwordHash));
  if (!valid) throw new AppError('Username atau password salah', 401);
  if (!user.isActive) throw new AppError('Akun Anda dinonaktifkan', 403);

  res.json({
    user: publicUser(user),
    accessToken: signAccessToken(user),
    refreshToken: signRefreshToken(user),
  });
}

async function refresh(req, res) {
  const { refreshToken } = refreshSchema.parse(req.body);

  let payload;
  try {
    payload = verifyRefreshToken(refreshToken);
  } catch (e) {
    throw new AppError('Refresh token tidak valid atau kedaluwarsa', 401);
  }

  const user = await prisma.user.findUnique({
    where: { id: Number(payload.sub) },
    include: { role: true },
  });
  if (!user || !user.isActive) throw new AppError('Akun tidak aktif', 401);

  res.json({
    accessToken: signAccessToken(user),
    refreshToken: signRefreshToken(user),
  });
}

async function me(req, res) {
  res.json({ user: req.user });
}

async function changePassword(req, res) {
  const { oldPassword, newPassword } = changePasswordSchema.parse(req.body);

  const user = await prisma.user.findUnique({ where: { id: req.user.id } });
  const ok = await bcrypt.compare(oldPassword, user.passwordHash);
  if (!ok) throw new AppError('Password lama salah', 400);

  await prisma.user.update({
    where: { id: user.id },
    data: { passwordHash: await bcrypt.hash(newPassword, 12) },
  });

  res.json({ message: 'Password berhasil diganti' });
}

module.exports = { login, refresh, me, changePassword };