const router = require('express').Router();
const ctrl = require('../controllers/cash.controller');
const { authenticate, authorize } = require('../middleware/auth');
const { resolveScope } = require('../middleware/scope');

router.use(authenticate, resolveScope);

router.get('/', authorize('OWNER', 'CASHIER'), ctrl.overview);
router.post('/deposits', authorize('CASHIER'), ctrl.createDeposit);
router.post('/deposits/:id/confirm', authorize('OWNER'), ctrl.confirmDeposit);

module.exports = router;