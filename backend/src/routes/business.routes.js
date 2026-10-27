const router = require('express').Router();
const ctrl = require('../controllers/business.controller');
const { authenticate, authorize } = require('../middleware/auth');

router.get('/', authenticate, ctrl.get);
router.patch('/', authenticate, authorize('OWNER'), ctrl.update);

module.exports = router;