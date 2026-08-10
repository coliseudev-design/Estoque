const express = require('express');
const router = express.Router();
const erpConfigService = require('../services/erp-config.service');
const { requireInternalAuth } = require('../middleware/auth');

// ─────────────────────────────────────────────────────────────────────────────
// Sincronização vinda do Worker (Firebird -> VPS)
// ─────────────────────────────────────────────────────────────────────────────

router.post('/payment-species/sync', requireInternalAuth, async (req, res, next) => {
  try {
    const tenantId = req.tenant.id;
    const items = req.body.species || req.body;
    if (!Array.isArray(items)) {
      return res.status(400).json({ error: 'Payload deve ser um array de espécies de pagamento' });
    }
    const count = await erpConfigService.upsertPaymentSpecies(tenantId, items);
    res.json({ success: true, count });
  } catch (error) {
    next(error);
  }
});

router.post('/payment-conditions/sync', requireInternalAuth, async (req, res, next) => {
  try {
    const tenantId = req.tenant.id;
    const items = req.body.conditions || req.body;
    if (!Array.isArray(items)) {
      return res.status(400).json({ error: 'Payload deve ser um array de condições de pagamento' });
    }
    const count = await erpConfigService.upsertPaymentConditions(tenantId, items);
    res.json({ success: true, count });
  } catch (error) {
    next(error);
  }
});

router.post('/naturezas/sync', requireInternalAuth, async (req, res, next) => {
  try {
    const tenantId = req.tenant.id;
    const items = req.body.naturezas || req.body;
    if (!Array.isArray(items)) {
      return res.status(400).json({ error: 'Payload deve ser um array de naturezas de operação' });
    }
    const count = await erpConfigService.upsertNaturezasOperacao(tenantId, items);
    res.json({ success: true, count });
  } catch (error) {
    next(error);
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Consulta passiva para o Mobile (PULL)
// ─────────────────────────────────────────────────────────────────────────────

router.get('/payment-species', async (req, res, next) => {
  try {
    const tenantId = req.query.tenantId || req.tenant?.id || '1e40d65f-4319-4c68-ae13-66223820c095';
    const data = await erpConfigService.getPaymentSpecies(tenantId);
    res.json({ success: true, data });
  } catch (error) {
    next(error);
  }
});

router.get('/payment-conditions', async (req, res, next) => {
  try {
    const tenantId = req.query.tenantId || req.tenant?.id || '1e40d65f-4319-4c68-ae13-66223820c095';
    const data = await erpConfigService.getPaymentConditions(tenantId);
    res.json({ success: true, data });
  } catch (error) {
    next(error);
  }
});

router.get('/naturezas', async (req, res, next) => {
  try {
    const tenantId = req.query.tenantId || req.tenant?.id || '1e40d65f-4319-4c68-ae13-66223820c095';
    const data = await erpConfigService.getNaturezasOperacao(tenantId);
    res.json({ success: true, data });
  } catch (error) {
    next(error);
  }
});

module.exports = router;
