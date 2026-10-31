const router = require('express').Router();
const rateLimit = require('express-rate-limit');
const ctrl = require('../controllers/auth.controller');
const { authenticate } = require('../middleware/auth');
const { resolveScope } = require('../middleware/scope');

// Batasi percobaan login: maks 20 kali gagal per 15 menit per IP
const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 20,
  skipSuccessfulRequests: true,
  standardHeaders: true,
  legacyHeaders: false,
  message: { message: 'Terlalu banyak percobaan login, coba lagi nanti' },
});

// Batasi pendaftaran: maks 10 kali per jam per IP
const registerLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  limit: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { message: 'Terlalu banyak pendaftaran dari jaringan ini, coba lagi nanti' },
});

router.post('/register', registerLimiter, ctrl.register);
router.post('/login', loginLimiter, ctrl.login); // lama, dihapus di tahap berikutnya
router.post('/login/owner', loginLimiter, ctrl.loginOwner);
router.post('/login/cashier', loginLimiter, ctrl.loginCashier);
router.post('/refresh', ctrl.refresh);
router.get('/me', authenticate, resolveScope, ctrl.me);
router.patch('/password', authenticate, ctrl.changePassword);

module.exports = router;
