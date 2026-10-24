const router = require('express').Router();
const ctrl = require('../controllers/expenses.controller');
const { authenticate, authorize } = require('../middleware/auth');

router.use(authenticate, authorize('OWNER'));

router.get('/categories', ctrl.categories); // harus di atas '/:id'
router.get('/', ctrl.list);
router.post('/', ctrl.create);
router.patch('/:id', ctrl.update);
router.delete('/:id', ctrl.remove);

module.exports = router;