const router = require('express').Router();
const ctrl = require('../controllers/options.controller');
const { authenticate, authorize } = require('../middleware/auth');
const { resolveScope } = require('../middleware/scope');

router.use(authenticate, resolveScope);

router.get('/', authorize('OWNER', 'CASHIER'), ctrl.list);
router.post('/', authorize('OWNER'), ctrl.create);
router.patch('/:id', authorize('OWNER'), ctrl.update);

module.exports = router;