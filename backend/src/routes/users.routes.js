const router = require('express').Router();
const ctrl = require('../controllers/users.controller');
const { authenticate, authorize } = require('../middleware/auth');

// Semua rute di sini khusus OWNER
router.use(authenticate, authorize('OWNER'));

router.get('/', ctrl.list);
router.post('/', ctrl.create);
router.patch('/:id', ctrl.update);
router.post('/:id/reset-password', ctrl.resetPassword);

module.exports = router;