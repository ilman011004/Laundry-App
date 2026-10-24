const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const rateLimit = require('express-rate-limit');

const env = require('./config/env');
const prisma = require('./lib/prisma');
const { notFound, errorHandler } = require('./middleware/errorHandler');

const app = express();

app.use(helmet());
app.use(cors());
app.use(express.json({ limit: '1mb' }));
if (env.NODE_ENV !== 'test') app.use(morgan('dev'));

app.use(
  rateLimit({
    windowMs: 60 * 1000,
    limit: 300,
    standardHeaders: true,
    legacyHeaders: false,
  })
);

app.get('/health', async (req, res) => {
  try {
    await prisma.$queryRaw`SELECT 1`;
    res.json({ status: 'ok', database: 'up', time: new Date().toISOString() });
  } catch (e) {
    res.status(503).json({ status: 'error', database: 'down' });
  }
});

app.use('/api/auth', require('./routes/auth.routes'));
app.use('/api/users', require('./routes/users.routes'));
app.use('/api/customers', require('./routes/customers.routes'));
app.use('/api/services', require('./routes/services.routes'));
app.use('/api/options', require('./routes/options.routes'));
app.use('/api/catalog', require('./routes/catalog.routes'));

app.use(notFound);
app.use(errorHandler);

module.exports = app;