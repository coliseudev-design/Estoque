-- ============================================================================
-- 009_pending_customers.sql — Clientes pendentes de cadastro no ERP.
--
-- Fluxo: Mobile → POST /api/sync/new-customer → salva aqui
--        Worker → GET /api/sync/pending-customers → busca aqui
--        Worker → MOB_CADASTRA_CLIENTE (Firebird) → confirma aqui
--
-- Segue o mesmo padrão da tabela orders (sync_status + payload).
-- ============================================================================

CREATE TABLE IF NOT EXISTS pending_customers (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id      UUID        NOT NULL REFERENCES companies("Id") ON DELETE CASCADE,
    sync_status     TEXT        NOT NULL DEFAULT 'pending'
                                CHECK (sync_status IN ('pending','synced','error')),
    local_id        TEXT,                              -- ID local do mobile (local_xxxx)
    erp_customer_id TEXT,                              -- ID real do ERP (preenchido pelo Worker)
    payload         JSONB       NOT NULL DEFAULT '{}', -- Dados completos do cliente
    error_message   TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Índices para queries frequentes
CREATE INDEX IF NOT EXISTS idx_pending_customers_company_status
    ON pending_customers(company_id, sync_status);

-- RLS
ALTER TABLE pending_customers ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_pending_customers ON pending_customers
    FOR ALL
    USING (company_id::text = current_setting('app.current_company_id', TRUE));

GRANT SELECT, INSERT, UPDATE ON pending_customers TO app_user;

-- Trigger updated_at (reutiliza função set_updated_at de 002_orders.sql)
CREATE TRIGGER pending_customers_updated_at
    BEFORE UPDATE ON pending_customers
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
