const router = require('express').Router();
const ctrl = require('../controllers/photos.controller');
const { authenticate, authorize } = require('../middleware/auth');
const { resolveScope } = require('../middleware/scope');

router.use(authenticate, authorize('OWNER', 'CASHIER'), resolveScope);

router.get('/:id/file', ctrl.file);

module.exports = router;