const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const multer = require('multer');
const { z } = require('zod');
const prisma = require('../lib/prisma');
const { AppError } = require('../middleware/errorHandler');

const fsp = fs.promises;

// Foto disimpan di backend/uploads/orders/<id pesanan>/
const UPLOAD_ROOT = path.resolve(__dirname, '../../uploads');
const MAX_BYTES = 8 * 1024 * 1024;
const MAX_PER_KIND = 10;

const idParam = z.object({ id: z.coerce.number().int().positive() });
const kindSchema = z.object({ kind: z.enum(['RECEIVED', 'READY']) });

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_BYTES, files: 1 },
});

// Mengubah error multer menjadi pesan bahasa Indonesia
function uploadMiddleware(req, res, next) {
  upload.single('photo')(req, res, (err) => {
    if (!err) return next();
    if (err instanceof multer.MulterError) {
      if (err.code === 'LIMIT_FILE_SIZE') {
        return next(new AppError('Ukuran foto maksimal 8 MB', 413));
      }
      return next(new AppError('Unggahan foto tidak valid', 400));
    }
    return next(err);
  });
}

// Jenis file dikenali dari isinya, bukan dari nama atau tipe kiriman klien
function detectImage(buf) {
  if (buf.length < 12) return null;
  if (buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) {
    return { ext: 'jpg', mime: 'image/jpeg' };
  }
  if (buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) {
    return { ext: 'png', mime: 'image/png' };
  }
  if (buf.subarray(0, 4).toString('ascii') === 'RIFF' && buf.subarray(8, 12).toString('ascii') === 'WEBP') {
    return { ext: 'webp', mime: 'image/webp' };
  }
  return null;
}

function format(p) {
  return {
    id: p.id,
    orderId: p.orderId,
    kind: p.kind,
    sizeBytes: p.sizeBytes,
    createdAt: p.createdAt,
  };
}

async function create(req, res) {
  const { id } = idParam.parse(req.params);
  const { kind } = kindSchema.parse({ ...req.body });
  if (!req.file) throw new AppError('File foto wajib dikirim', 400);

  const type = detectImage(req.file.buffer);
  if (!type) throw new AppError('File harus berupa foto (JPG, PNG, atau WebP)', 400);

  const order = await prisma.order.findUnique({
    where: { id },
    select: { id: true, workStatus: true },
  });
  if (!order) throw new AppError('Pesanan tidak ditemukan', 404);
  if (order.workStatus === 'CANCELLED') throw new AppError('Pesanan sudah dibatalkan', 409);
  if (kind === 'READY' && order.workStatus !== 'READY') {
    throw new AppError('Foto siap diambil hanya bisa ditambahkan saat status pesanan Siap', 409);
  }

  const count = await prisma.orderPhoto.count({ where: { orderId: id, kind } });
  if (count >= MAX_PER_KIND) {
    throw new AppError(`Maksimal ${MAX_PER_KIND} foto untuk jenis ini`, 409);
  }

  const dir = path.join(UPLOAD_ROOT, 'orders', String(id));
  await fsp.mkdir(dir, { recursive: true });
  const filename = `${crypto.randomUUID()}.${type.ext}`;
  const fullPath = path.join(dir, filename);
  await fsp.writeFile(fullPath, req.file.buffer, { flag: 'wx' });

  try {
    const photo = await prisma.orderPhoto.create({
      data: {
        orderId: id,
        kind,
        filename,
        mimeType: type.mime,
        sizeBytes: req.file.size,
        uploadedById: req.user.id,
      },
    });
    res.status(201).json({ data: format(photo) });
  } catch (e) {
    await fsp.unlink(fullPath).catch(() => {});
    throw e;
  }
}

async function list(req, res) {
  const { id } = idParam.parse(req.params);
  const photos = await prisma.orderPhoto.findMany({
    where: { orderId: id },
    orderBy: { id: 'asc' },
  });
  res.json({ data: photos.map(format) });
}

async function file(req, res, next) {
  const { id } = idParam.parse(req.params);
  const photo = await prisma.orderPhoto.findUnique({ where: { id } });
  if (!photo) throw new AppError('Foto tidak ditemukan', 404);

  const full = path.join(UPLOAD_ROOT, 'orders', String(photo.orderId), photo.filename);
  res.set('Cache-Control', 'private, max-age=86400');
  res.type(photo.mimeType);
  res.sendFile(full, (err) => {
    if (err && !res.headersSent) {
      next(new AppError('Berkas foto tidak ditemukan di server', 404));
    }
  });
}

module.exports = { uploadMiddleware, create, list, file };