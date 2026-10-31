const router = require('express').Router();
const ctrl = require('../controllers/orders.controller');
const payments = require('../controllers/payments.controller');
const status = require('../controllers/orderStatus.controller');
const photos = require('../controllers/photos.controller');
const { authenticate, authorize } = require('../middleware/auth');
const { resolveScope } = require('../middleware/scope');

router.use(authenticate, authorize('OWNER', 'CASHIER'), resolveScope);

router.post('/preview', ctrl.preview);
router.get('/', ctrl.list);
router.post('/', ctrl.create);
router.get('/:id', ctrl.detail);

// Empat route di bawah ini baru diisolasi di 18c-3
router.get('/:id/payments', payments.list);
router.post('/:id/payments', payments.create);
router.patch('/:id/status', status.update);
router.post('/:id/cancel', authorize('OWNER'), status.cancel);

router.get('/:id/photos', photos.list);
router.post('/:id/photos', photos.uploadMiddleware, photos.create);

module.exports = router;