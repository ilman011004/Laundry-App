const router = require('express').Router();
const ctrl = require('../controllers/dashboard.controller');
const { authenticate, authorize } = require('../middleware/auth');
const { resolveScope } = require('../middleware/scope');

router.get('/', authenticate, authorize('OWNER', 'CASHIER'), resolveScope, ctrl.summary);

module.exports = router;