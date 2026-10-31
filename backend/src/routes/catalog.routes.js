const router = require('express').Router();
const ctrl = require('../controllers/catalog.controller');
const { authenticate, authorize } = require('../middleware/auth');
const { resolveScope } = require('../middleware/scope');

router.get('/', authenticate, authorize('OWNER', 'CASHIER'), resolveScope, ctrl.get);

module.exports = router;