const express = require('express');
const router = express.Router();
const catalogService = require('../services/catalog.service');
const { requireInternalAuth, requireDeviceJwt } = require('../middleware/auth');

/**
 * @route   POST /internal/catalog/sync
 * @desc    Sincroniza produtos/serviços do Worker (Firebird) em lote
 * @access  Internal (Worker)
 */
router.post('/sync', requireInternalAuth, async (req, res, next) => {
  try {
    const tenantId = req.tenant.id; // Injetado pelo requireInternalAuth
    const items = req.body;

    if (!Array.isArray(items)) {
      return res.status(400).json({ error: 'Payload deve ser um array de itens de catálogo' });
    }

    const insertedCount = await catalogService.upsertBatch(tenantId, items);

    res.json({
      success: true,
      message: `Sync de Catálogo concluído`,
      syncedCount: insertedCount
    });

  } catch (error) {
    next(error);
  }
});

/**
 * @route   GET /api/catalog
 * @desc    PULL passivo dos produtos disponíveis (Para o Mobile)
 * @access  Private (Mobile App)
 */
router.get('/', async (req, res, next) => {
  try {
    const tenantId = req.query.tenantId || req.tenant?.id || '1e40d65f-4319-4c68-ae13-66223820c095';
    const since = req.query.since;

    const catalog = await catalogService.getActiveCatalog(tenantId, since);

    res.json({
      success: true,
      count: catalog.length,
      data: catalog
    });
  } catch (error) {
    next(error);
  }
});

module.exports = router;
