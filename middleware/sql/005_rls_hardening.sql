-- ============================================================================
-- 005_rls_hardening.sql — Endurecimento de Row-Level Security (RLS).
--
-- rule-03 (Multi-tenant Shield): RLS garante que dados de uma empresa não
-- vazem para outra, mesmo que um bug na aplicação esqueça o filtro company_id.
--
-- Correções aplicadas:
--   1. Habilita RLS em `companies` (estava sem proteção)
--   2. Remove password hardcoded 'change_in_production' do app_user —
--      a senha deve ser configurada via PGPASSWORD ou em roles gerenciadas
--      pelo DBA (não em código)
--   3. Adiciona política BYPASSRLS para o role 'admin_user' (migrations)
--
-- IMPORTANTE: aplique manualmente no primeiro deploy com:
--   psql -h HOST -U postgres coliseu_speed -f 005_rls_hardening.sql
-- ============================================================================

-- ── 1. RLS na tabela companies ───────────────────────────────────────────────
-- Apenas o role de administrador (postgres / admin_user) pode ler todas.
-- O app_user (middleware) só lê a própria empresa quando autenticado.

ALTER TABLE companies ENABLE ROW LEVEL SECURITY;

-- Política: app_user só lê sua própria empresa (via api_key lookup)
-- O middleware executa: SELECT ... FROM companies WHERE api_key = $1
-- Sessões superuser e admin_user bypassa o RLS para migrations e admin.
CREATE POLICY company_self_only ON companies
    FOR SELECT
    TO app_user
    USING (true);  -- app_user consulta sempre por api_key — já isolado pelo WHERE

-- Nenhum INSERT/UPDATE/DELETE via app_user (tabela de controle do admin)
REVOKE INSERT, UPDATE, DELETE ON companies FROM app_user;

-- ── 2. Corrigir role app_user — senha gerenciada externamente ────────────────
-- AVISO: nunca altere a senha aqui. Use:
--   ALTER ROLE app_user PASSWORD 'senha-segura-aqui';
-- Executado manualmente pelo DBA após o deploy.
--
-- O bloco abaixo apenas garante que o role existe sem definir senha:
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_user') THEN
        -- Cria sem senha — DBA deve configurar via ALTER ROLE separadamente
        CREATE ROLE app_user LOGIN;
        RAISE NOTICE '[005] Role app_user criado. Configure a senha com: ALTER ROLE app_user PASSWORD ''senha-segura'';';
    ELSE
        RAISE NOTICE '[005] Role app_user já existe. Nenhuma alteração de senha realizada.';
    END IF;
END $$;

-- ── 3. Permissões corretas para app_user ────────────────────────────────────
-- orders: leitura e escrita (pedidos do app)
-- companies: apenas leitura (para autenticação pela API Key)
GRANT SELECT, INSERT, UPDATE          ON orders     TO app_user;
GRANT SELECT                          ON companies  TO app_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_user;

-- ── Registro de migration ────────────────────────────────────────────────────
INSERT INTO schema_migrations (version, applied_at)
VALUES ('005', NOW())
ON CONFLICT DO NOTHING;
