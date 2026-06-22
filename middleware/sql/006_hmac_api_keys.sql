-- ============================================================================
-- 006_hmac_api_keys.sql — Migração de SHA-256 simples para HMAC-SHA-256.
--
-- rule-04 (Cofre de Segredos): SHA-256 puro é determinístico e suscetível
-- a rainbow tables. HMAC com salt por empresa adiciona uma segunda camada
-- de proteção se o banco for comprometido.
--
-- IMPORTANTE: Esta migration INVALIDA todas as API Keys existentes.
-- FLUXO DE MIGRAÇÃO SEGURA:
--   1. Execute este script em staging primeiro
--   2. Atualize o middleware auth.js para usar HMAC ao fazer lookup
--   3. Rode o script Node abaixo para rotacionar as keys de empresas reais:
--      node scripts/rotate_all_keys.js --admin-key <ADMIN_KEY>
--   4. Distribua as novas keys para os Workers de cada empresa
--   5. Aplique em produção
--
-- ALTERNATIVA (sem invalidar keys existentes):
--   Adicionar coluna `api_key_hmac` e migrar gradualmente empresa por empresa.
-- ============================================================================

-- ── Passo 1: Adicionar coluna HMAC (migração aditiva — não destrutiva) ────────

-- Adiciona coluna hmac preservando a coluna sha256 existente
ALTER TABLE companies ADD COLUMN IF NOT EXISTS api_key_hmac TEXT;

-- ── Passo 2: Criar função de lookup por HMAC ──────────────────────────────────
-- O middleware Node.js calculará: HMAC-SHA256(rawKey, HMAC_SECRET)
-- e buscará por api_key_hmac em vez de api_key (sha256)

-- Índice para a nova coluna de lookup (ainda NULL até rotação das keys)
CREATE INDEX IF NOT EXISTS idx_companies_api_key_hmac ON companies(api_key_hmac)
    WHERE api_key_hmac IS NOT NULL;

-- ── Passo 3: Documentação da migração ────────────────────────────────────────
-- Após a rotação de todas as empresas:
--   1. Renomear: api_key → api_key_sha256_deprecated
--   2. Renomear: api_key_hmac → api_key
--   3. DROP INDEX idx_companies_api_key
--   4. DROP COLUMN api_key_sha256_deprecated
--   Isso requer downtime de ~30 segundos ou uma migration com bloqueio de escrita.

-- ── Registro de migration ─────────────────────────────────────────────────────
INSERT INTO schema_migrations (version, applied_at)
VALUES ('006', NOW())
ON CONFLICT DO NOTHING;
