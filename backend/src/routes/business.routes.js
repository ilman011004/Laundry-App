const router = require('express').Router();
const ctrl = require('../controllers/business.controller');
const { authenticate, authorize } = require('../middleware/auth');
const { resolveScope } = require('../middleware/scope');

router.get('/', authenticate, authorize('OWNER', 'CASHIER'), resolveScope, ctrl.get);
router.patch('/', authenticate, authorize('OWNER'), resolveScope, ctrl.update);

module.exports = router;