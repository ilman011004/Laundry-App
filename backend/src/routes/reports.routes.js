const router = require('express').Router();
const ctrl = require('../controllers/reports.controller');
const { authenticate, authorize } = require('../middleware/auth');

router.use(authenticate, authorize('OWNER'));

router.get('/dashboard', ctrl.dashboard);
router.get('/summary', ctrl.summary);

module.exports = router;