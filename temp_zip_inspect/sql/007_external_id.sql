-- ============================================================================
-- 007_external_id.sql — Adiciona external_id à tabela companies.
--
-- external_id: UUID da empresa no Coliseu.Identity (sistema de IAM).
-- Permite que a Identity API notifique o middleware ao rotar a API Key,
-- sem precisar conhecer o UUID interno do middleware.
-- ============================================================================

ALTER TABLE companies ADD COLUMN IF NOT EXISTS external_id UUID UNIQUE;

CREATE INDEX IF NOT EXISTS idx_companies_external_id ON companies(external_id)
    WHERE external_id IS NOT NULL;

INSERT INTO schema_migrations (version, applied_at)
VALUES ('007', NOW())
ON CONFLICT DO NOTHING;
