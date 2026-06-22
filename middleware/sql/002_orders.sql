-- ============================================================================
-- 002_orders.sql — Tabela de pedidos multi-tenant com company_id + RLS.
--
-- Substitui o orderIndex em memória (better-sqlite3) pelo PostgreSQL.
-- Cada pedido é vinculado à empresa pelo company_id, garantindo isolamento.
--
-- Row-Level Security (RLS):
--   Mesmo que uma query esqueça o WHERE company_id = $1, o RLS bloqueia.
--   A aplicação conecta como role 'app_user' que só vê sua empresa.
-- ============================================================================

CREATE TABLE IF NOT EXISTS orders (
    id              TEXT        PRIMARY KEY,        -- UUID do pedido (gerado pelo Flutter)
    company_id      UUID        NOT NULL REFERENCES companies("Id") ON DELETE CASCADE,
    sync_status     TEXT        NOT NULL DEFAULT 'pending'
                                CHECK (sync_status IN ('pending','synced','error')),
    erp_order_id    TEXT,                           -- Número ERP Firebird (preenchido pelo Worker)
    error_message   TEXT,
    customer_name   TEXT,
    seller_name     TEXT,
    total_amount    NUMERIC(12,2) NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Índices para queries frequentes
CREATE INDEX IF NOT EXISTS idx_orders_company_status
    ON orders(company_id, sync_status);

CREATE INDEX IF NOT EXISTS idx_orders_company_created
    ON orders(company_id, created_at DESC);

-- ── Row-Level Security ───────────────────────────────────────────────────────

ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- Política: cada role_company_{id} só lê/escreve seus próprios pedidos
-- O middleware seta: SET LOCAL app.current_company_id = '{uuid}' antes de cada query
CREATE POLICY tenant_isolation ON orders
    FOR ALL
    USING (company_id::text = current_setting('app.current_company_id', TRUE));

-- Role para a aplicação (sem superuser)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_user') THEN
        CREATE ROLE app_user LOGIN PASSWORD 'change_in_production';
    END IF;
END $$;

GRANT SELECT, INSERT, UPDATE ON orders     TO app_user;
GRANT SELECT                  ON companies TO app_user;
GRANT USAGE, SELECT           ON ALL SEQUENCES IN SCHEMA public TO app_user;

-- ── Função para updated_at automático ───────────────────────────────────────

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER orders_updated_at
    BEFORE UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
