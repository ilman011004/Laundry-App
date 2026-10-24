const prisma = require('../lib/prisma');
const { AppError } = require('./errorHandler');
const { verifyAccessToken } = require('../utils/jwt');

// Cek token di header "Authorization: Bearer <token>"
async function authenticate(req, res, next) {
  const header = req.headers.authorization || '';
  const [scheme, token] = header.split(' ');

  if (scheme !== 'Bearer' || !token) {
    throw new AppError('Token tidak ditemukan', 401);
  }

  let payload;
  try {
    payload = verifyAccessToken(token);
  } catch (e) {
    throw new AppError('Token tidak valid atau sudah kedaluwarsa', 401);
  }

  // Cek ke database supaya akun yang dinonaktifkan langsung tidak bisa dipakai
  const user = await prisma.user.findUnique({
    where: { id: Number(payload.sub) },
    include: { role: true },
  });

  if (!user || !user.isActive) {
    throw new AppError('Akun tidak ditemukan atau nonaktif', 401);
  }

  req.user = {
    id: user.id,
    name: user.name,
    username: user.username,
    role: user.role.name,
  };
  next();
}

// Batasi akses berdasarkan role. Contoh: authorize('OWNER', 'CASHIER')
function authorize(...allowedRoles) {
  return (req, res, next) => {
    if (!req.user || !allowedRoles.includes(req.user.role)) {
      throw new AppError('Anda tidak memiliki akses ke fitur ini', 403);
    }
    next();
  };
}

module.exports = { authenticate, authorize };