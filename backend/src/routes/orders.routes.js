const router = require('express').Router();
const ctrl = require('../controllers/orders.controller');
const payments = require('../controllers/payments.controller');
const status = require('../controllers/orderStatus.controller');
const { authenticate, authorize } = require('../middleware/auth');

router.use(authenticate, authorize('OWNER', 'CASHIER'));

// Tahap 5: pesanan
router.post('/preview', ctrl.preview);
router.get('/', ctrl.list);
router.post('/', ctrl.create);
router.get('/:id', ctrl.detail);

// Tahap 6: pembayaran
router.get('/:id/payments', payments.list);
router.post('/:id/payments', payments.create);

// Tahap 6: status pengerjaan
router.patch('/:id/status', status.update);
router.post('/:id/cancel', authorize('OWNER'), status.cancel);

module.exports = router;