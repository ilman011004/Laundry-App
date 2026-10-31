const bcrypt = require('bcryptjs');
const { z } = require('zod');
const prisma = require('../lib/prisma');
const { AppError } = require('../middleware/errorHandler');
const { generateBusinessCode } = require('../utils/businessCode');
const { normalizeTimezone } = require('../utils/time');
const {
  signAccessToken,
  signRefreshToken,
  verifyRefreshToken,
} = require('../utils/jwt');

const emailField = z
  .string()
  .trim()
  .toLowerCase()
  .email('Format email tidak valid')
  .max(120);

const legacyLoginSchema = z.object({
  username: z.string().trim().min(1, 'Username wajib diisi'),
  password: z.string().min(1, 'Password wajib diisi'),
});

const ownerLoginSchema = z.object({
  email: emailField,
  password: z.string().min(1, 'Password wajib diisi'),
});

const cashierLoginSchema = z.object({
  businessCode: z.string().trim().toUpperCase().min(1, 'Kode usaha wajib diisi'),
  username: z.string().trim().toLowerCase().min(1, 'Username wajib diisi'),
  password: z.string().min(1, 'Password wajib diisi'),
});

const registerSchema = z.object({
  name: z.string().trim().min(2, 'Nama minimal 2 karakter').max(60),
  email: emailField,
  password: z
    .string()
    .min(8, 'Password minimal 8 karakter')
    .max(72, 'Password maksimal 72 karakter'),
  businessName: z.string().trim().min(2, 'Nama usaha minimal 2 karakter').max(60),
  phone: z.string().trim().max(30).optional(),
  timezone: z.string().trim().max(60).optional(),
});

const refreshSchema = z.object({
  refreshToken: z.string().min(1),
});

const changePasswordSchema = z.object({
  oldPassword: z.string().min(1),
  newPassword: z.string().min(8, 'Password baru minimal 8 karakter'),
});

const fullInclude = {
  role: true,
  business: true,
  outlet: true,
};

// Hash palsu untuk membandingkan password saat akun tidak ditemukan,
// supaya waktu respons sama dan keberadaan akun tidak bocor.
const DUMMY_HASH = bcrypt.hashSync('tidak-dipakai', 12);

async function checkPassword(user, password) {
  const ok = await bcrypt.compare(password, user ? user.passwordHash : DUMMY_HASH);
  return Boolean(user) && ok;
}

function publicUser(user) {
  const isOwner = user.role.name === 'OWNER';
  return {
    id: user.id,
    name: user.name,
    username: user.username,
    email: user.email,
    role: user.role.name,
    businessId: user.businessId,
    outletId: user.outletId,
    business: user.business
      ? {
          id: user.business.id,
          name: user.business.name,
          timezone: user.business.timezone,
          // Kode usaha hanya untuk pemilik (dibagikan ke kasir)
          ...(isOwner ? { code: user.business.code } : {}),
        }
      : null,
    outlet: user.outlet ? { id: user.outlet.id, name: user.outlet.name } : null,
  };
}

function assertCanLogin(user) {
  if (!user.isActive) throw new AppError('Akun Anda dinonaktifkan', 403);
  if (user.outlet && !user.outlet.isActive) {
    throw new AppError('Outlet Anda dinonaktifkan. Hubungi pemilik.', 403);
  }
}

function sendSession(res, user, status = 200) {
  res.status(status).json({
    user: publicUser(user),
    accessToken: signAccessToken(user),
    refreshToken: signRefreshToken(user),
  });
}

// ---------- Login lama (username dan password), tetap ada agar aplikasi lama jalan ----------
async function login(req, res) {
  const { username, password } = legacyLoginSchema.parse(req.body);

  const user = await prisma.user.findFirst({
    where: { username },
    include: fullInclude,
  });

  if (!(await checkPassword(user, password))) {
    throw new AppError('Username atau password salah', 401);
  }
  assertCanLogin(user);
  sendSession(res, user);
}

// ---------- Login pemilik: email dan password ----------
async function loginOwner(req, res) {
  const { email, password } = ownerLoginSchema.parse(req.body);

  const user = await prisma.user.findUnique({
    where: { email },
    include: fullInclude,
  });

  if (!(await checkPassword(user, password))) {
    throw new AppError('Email atau password salah', 401);
  }
  if (user.role.name !== 'OWNER') {
    throw new AppError('Ini bukan akun Pemilik. Silakan masuk lewat tab Kasir.', 403);
  }
  assertCanLogin(user);
  sendSession(res, user);
}

// ---------- Login kasir: kode usaha, username, dan password ----------
async function loginCashier(req, res) {
  const { businessCode, username, password } = cashierLoginSchema.parse(req.body);

  const user = await prisma.user.findFirst({
    where: { username, business: { code: businessCode } },
    include: fullInclude,
  });

  if (!(await checkPassword(user, password))) {
    throw new AppError('Kode usaha, username, atau password salah', 401);
  }
  if (user.role.name === 'OWNER') {
    throw new AppError('Ini akun Pemilik. Silakan masuk lewat tab Pemilik.', 403);
  }
  assertCanLogin(user);
  sendSession(res, user);
}

// ---------- Pendaftaran pemilik baru ----------
async function register(req, res) {
  if (process.env.ALLOW_REGISTRATION !== 'true') {
    throw new AppError('Pendaftaran owner baru belum dibuka', 403);
  }

  const body = registerSchema.parse(req.body);

  const role = await prisma.role.findUnique({ where: { name: 'OWNER' } });
  if (!role) throw new AppError('Peran OWNER belum tersedia di database', 500);

  const existing = await prisma.user.findUnique({ where: { email: body.email } });
  if (existing) throw new AppError('Email sudah terdaftar', 409);

  const passwordHash = await bcrypt.hash(body.password, 12);

  let user = null;
  for (let attempt = 0; attempt < 5; attempt++) {
    try {
      user = await prisma.$transaction(async (tx) => {
        const business = await tx.business.create({
          data: {
            name: body.businessName,
            code: generateBusinessCode(),
            timezone: normalizeTimezone(body.timezone),
            phone: body.phone || '',
          },
        });

        await tx.outlet.create({
          data: {
            businessId: business.id,
            name: 'Outlet Utama',
            phone: body.phone || '',
          },
        });

        return tx.user.create({
          data: {
            name: body.name,
            username: body.email, // pemilik masuk dengan email; username diisi sama
            email: body.email,
            passwordHash,
            roleId: role.id,
            businessId: business.id,
          },
          include: fullInclude,
        });
      });
      break;
    } catch (e) {
      if (e.code === 'P2002') {
        const target = String(e.meta?.target ?? '');
        if (target.includes('email') || target.includes('username')) {
          throw new AppError('Email sudah terdaftar', 409);
        }
        continue; // kode usaha bentrok, coba kode lain
      }
      throw e;
    }
  }

  if (!user) throw new AppError('Gagal membuat usaha, silakan coba lagi', 500);
  sendSession(res, user, 201);
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
    include: fullInclude,
  });
  if (!user || !user.isActive) throw new AppError('Akun tidak aktif', 401);

  res.json({
    accessToken: signAccessToken(user),
    refreshToken: signRefreshToken(user),
  });
}

// Butuh authenticate dan resolveScope di route (lihat auth.routes.js)
async function me(req, res) {
  const user = await prisma.user.findUnique({
    where: { id: req.user.id },
    include: fullInclude,
  });

  const data = {
    user: publicUser(user),
    timezone: req.scope.timezone,
    activeOutletId: req.scope.outletId,
  };
  // Daftar outlet untuk pemilih outlet di aplikasi (hanya owner)
  if (req.scope.isOwner) data.outlets = req.scope.outlets;

  res.json(data);
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

module.exports = {
  login,
  loginOwner,
  loginCashier,
  register,
  refresh,
  me,
  changePassword,
};