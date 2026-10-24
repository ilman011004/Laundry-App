const router = require('express').Router();
const ctrl = require('../controllers/orders.controller');
const { authenticate, authorize } = require('../middleware/auth');

router.use(authenticate, authorize('OWNER', 'CASHIER'));

router.post('/preview', ctrl.preview);
router.get('/', ctrl.list);
router.post('/', ctrl.create);
router.get('/:id', ctrl.detail);

module.exports = router;