const prisma = require('../lib/prisma');
const { AppError } = require('./errorHandler');
const { normalizeTimezone } = require('../utils/time');

// Dipasang SETELAH authenticate. Hasilnya req.scope:
// { businessId, outletId (angka atau null = semua outlet), outletActive, timezone, isOwner, outlets? }
async function resolveScope(req, res, next) {
  const { role, businessId, outletId } = req.user;
  const timezone = normalizeTimezone(req.user.timezone);

  // Kasir: outlet selalu dari akunnya sendiri, header X-Outlet-Id diabaikan
  if (role !== 'OWNER') {
    if (!outletId) throw new AppError('Akun Anda belum terikat ke outlet. Hubungi pemilik.', 403);
    req.scope = { businessId, outletId, outletActive: true, timezone, isOwner: false };
    return next();
  }

  // Owner: outlet dipilih lewat header X-Outlet-Id, harus milik usahanya
  const outlets = await prisma.outlet.findMany({
    where: { businessId },
    select: { id: true, name: true, isActive: true },
    orderBy: { id: 'asc' },
  });

  const raw = req.headers['x-outlet-id'];
  let active = null;

  if (raw !== undefined && raw !== '') {
    const id = Number(raw);
    active = Number.isInteger(id) ? outlets.find((o) => o.id === id) : null;
    if (!active) throw new AppError('Outlet tidak ditemukan di usaha Anda', 403);
  } else {
    // Tanpa header: kalau hanya ada satu outlet aktif, pakai itu
    const open = outlets.filter((o) => o.isActive);
    if (open.length === 1) active = open[0];
  }

  req.scope = {
    businessId,
    outletId: active ? active.id : null,
    outletActive: active ? active.isActive : false,
    timezone,
    isOwner: true,
    outlets,
  };
  next();
}

// Filter untuk tabel yang punya businessId dan outletId (pesanan, pengeluaran, setoran)
function outletScope(scope) {
  return scope.outletId
    ? { businessId: scope.businessId, outletId: scope.outletId }
    : { businessId: scope.businessId };
}

// Filter untuk data milik usaha (pelanggan, layanan, opsi)
function businessScope(scope) {
  return { businessId: scope.businessId };
}

// Untuk aksi tulis: harus ada satu outlet aktif yang jelas
function requireOutlet(scope) {
  if (!scope.outletId) {
    throw new AppError('Pilih outlet terlebih dahulu (usaha Anda punya lebih dari satu outlet)', 400);
  }
  if (!scope.outletActive) throw new AppError('Outlet ini dinonaktifkan', 409);
  return scope.outletId;
}

module.exports = { resolveScope, outletScope, businessScope, requireOutlet };