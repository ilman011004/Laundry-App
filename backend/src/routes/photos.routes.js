const router = require('express').Router();
const ctrl = require('../controllers/photos.controller');
const { authenticate, authorize } = require('../middleware/auth');

router.use(authenticate, authorize('OWNER', 'CASHIER'));

router.get('/:id/file', ctrl.file);

module.exports = router;