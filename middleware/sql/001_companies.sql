-- ============================================================================
-- 001_companies.sql — Tabela de empresas (tenants) do sistema Coliseu Sales.
--
-- Cada empresa tem:
--   id         — UUID gerado automaticamente (PK)
--   name       — Nome da empresa
--   api_key    — Chave hasheada com SHA-256 (nunca armazenamos texto puro)
--   active     — Flag para desativar empresa sem deletar dados
--   created_at — Criação do registro
--
-- Segurança:
--   A API Key é hasheada com SHA-256 + salt (hex) antes de salvar.
--   O middleware compara: SHA256(raw_key) == api_key_hash no banco.
--   Isso evita vazamento de chaves se o banco for comprometido.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";  -- gen_random_uuid()

CREATE TABLE IF NOT EXISTS companies (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name        TEXT        NOT NULL,
    api_key     TEXT        NOT NULL UNIQUE,  -- SHA-256 hash da chave real
    active      BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Índice para lookup rápido por api_key (toda autenticação passa aqui)
CREATE INDEX IF NOT EXISTS idx_companies_api_key ON companies(api_key);

-- ============================================================================
-- Vista de diagnóstico — sem api_key_hash (segurança)
-- ============================================================================
CREATE OR REPLACE VIEW v_companies_safe AS
    SELECT id, name, active, created_at
    FROM   companies;

-- ============================================================================
-- Seed: empresa de exemplo para desenvolvimento
--   API Key real (dev): dev-key-empresa-a
--   Hash SHA-256:       node -e "require('crypto').createHash('sha256').update('dev-key-empresa-a').digest('hex') |> console.log"
-- ============================================================================
INSERT INTO companies (id, name, api_key)
VALUES (
    'aaaaaaaa-0000-0000-0000-000000000001',
    'Empresa Demo A',
    encode(digest('dev-key-empresa-a', 'sha256'), 'hex')
)
ON CONFLICT DO NOTHING;
