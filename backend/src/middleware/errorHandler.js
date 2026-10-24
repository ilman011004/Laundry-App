const { ZodError } = require('zod');
const { Prisma } = require('@prisma/client');

class AppError extends Error {
  constructor(message, statusCode = 400, details = null) {
    super(message);
    this.statusCode = statusCode;
    this.details = details;
  }
}

function notFound(req, res) {
  res.status(404).json({ message: `Rute ${req.method} ${req.originalUrl} tidak ditemukan` });
}

// eslint-disable-next-line no-unused-vars
function errorHandler(err, req, res, next) {
  if (err instanceof AppError) {
    return res.status(err.statusCode).json({ message: err.message, details: err.details });
  }

  if (err instanceof ZodError) {
    return res.status(422).json({
      message: 'Data yang dikirim tidak valid',
      details: err.flatten().fieldErrors,
    });
  }

  if (err instanceof Prisma.PrismaClientKnownRequestError) {
    if (err.code === 'P2002') {
      return res.status(409).json({ message: 'Data sudah ada (duplikat)', details: err.meta });
    }
    if (err.code === 'P2025') {
      return res.status(404).json({ message: 'Data tidak ditemukan' });
    }
  }

  console.error(err);
  res.status(500).json({ message: 'Terjadi kesalahan pada server' });
}

module.exports = { AppError, notFound, errorHandler };