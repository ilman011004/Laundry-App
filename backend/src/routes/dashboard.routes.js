const router = require('express').Router();
const ctrl = require('../controllers/dashboard.controller');
const { authenticate, authorize } = require('../middleware/auth');

router.get('/', authenticate, authorize('OWNER', 'CASHIER'), ctrl.summary);

module.exports = router;