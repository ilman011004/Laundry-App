const router = require('express').Router();
const ctrl = require('../controllers/services.controller');
const { authenticate, authorize } = require('../middleware/auth');

router.use(authenticate);

router.get('/', authorize('OWNER', 'CASHIER'), ctrl.list);
router.post('/', authorize('OWNER'), ctrl.create);
router.patch('/:id', authorize('OWNER'), ctrl.update);

module.exports = router;