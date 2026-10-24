const router = require('express').Router();
const ctrl = require('../controllers/deliveries.controller');
const { authenticate, authorize } = require('../middleware/auth');

router.use(authenticate, authorize('OWNER', 'CASHIER'));

router.get('/', ctrl.list);
router.post('/', ctrl.create);
router.get('/:id', ctrl.detail);
router.patch('/:id', ctrl.update);
router.patch('/:id/status', ctrl.setStatus);

module.exports = router;