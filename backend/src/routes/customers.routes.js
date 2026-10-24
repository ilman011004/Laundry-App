const router = require('express').Router();
const ctrl = require('../controllers/customers.controller');
const { authenticate, authorize } = require('../middleware/auth');

router.use(authenticate, authorize('OWNER', 'CASHIER'));

router.get('/', ctrl.list);
router.post('/', ctrl.create);
router.get('/:id', ctrl.detail);
router.patch('/:id', ctrl.update);

router.post('/:id/addresses', ctrl.addAddress);
router.patch('/:id/addresses/:addressId', ctrl.updateAddress);
router.delete('/:id/addresses/:addressId', ctrl.removeAddress);

module.exports = router;