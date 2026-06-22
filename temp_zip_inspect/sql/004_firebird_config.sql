-- ============================================================================
-- 004_firebird_config.sql — Adiciona credenciais Firebird por empresa (tenant).
--
-- Cada empresa pode ter seu próprio banco Firebird (multi-tenant).
-- O middleware usa essas credenciais para criar pools dinâmicos de conexão.
--
-- Segurança (Rule-04):
--   fb_password é armazenado em AES-256-GCM pelo middleware antes de salvar.
--   Nunca em texto puro.
-- ============================================================================

ALTER TABLE companies
    ADD COLUMN IF NOT EXISTS fb_host     TEXT,
    ADD COLUMN IF NOT EXISTS fb_port     INTEGER DEFAULT 3050,
    ADD COLUMN IF NOT EXISTS fb_database TEXT,
    ADD COLUMN IF NOT EXISTS fb_user     TEXT    DEFAULT 'SYSDBA',
    ADD COLUMN IF NOT EXISTS fb_password TEXT,  -- criptografado AES-256-GCM
    ADD COLUMN IF NOT EXISTS fb_charset  TEXT    DEFAULT 'WIN1252',
    ADD COLUMN IF NOT EXISTS fb_wire_crypt BOOLEAN DEFAULT FALSE;

-- Vista segura atualizada (sem colunas sensíveis)
CREATE OR REPLACE VIEW v_companies_safe AS
    SELECT id, name, active, created_at,
           fb_host, fb_port, fb_database, fb_user, fb_charset,
           (fb_password IS NOT NULL) AS has_firebird_config
    FROM companies;
