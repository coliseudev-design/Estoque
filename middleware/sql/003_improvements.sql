-- ============================================================================
-- 003_schema_migrations.sql — Controle de versão de migrations (P1-A)
--
-- Garante que cada migration só seja executada uma vez.
-- O migrate.js verifica esta tabela antes de rodar cada arquivo SQL.
-- ============================================================================

CREATE TABLE IF NOT EXISTS schema_migrations (
    filename    TEXT        PRIMARY KEY,
    applied_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    checksum    TEXT        NOT NULL  -- SHA-256 do conteúdo SQL (detecta alterações)
);

-- ============================================================================
-- 004_order_events.sql — Audit trail de pedidos (P2-C)
--
-- Toda mudança de status de um pedido gera um registro aqui.
-- Permite rastrear: quem fez o quê, quando, com qual IP/fonte.
-- RLS: empresa só vê seus próprios eventos.
-- ============================================================================

CREATE TABLE IF NOT EXISTS order_events (
    id          BIGSERIAL   PRIMARY KEY,
    company_id  UUID        NOT NULL REFERENCES companies("Id") ON DELETE CASCADE,
    order_id    TEXT        NOT NULL,
    event_type  TEXT        NOT NULL, -- 'created','status_changed','confirmed','error'
    old_status  TEXT,
    new_status  TEXT        NOT NULL,
    metadata    JSONB,               -- dados extras (erpOrderId, errorMessage, etc.)
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_order_events_company_order
    ON order_events(company_id, order_id);

CREATE INDEX IF NOT EXISTS idx_order_events_company_created
    ON order_events(company_id, created_at DESC);

ALTER TABLE order_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation_events ON order_events
    FOR ALL
    USING (company_id::text = current_setting('app.current_company_id', TRUE));

-- Trigger: toda UPDATE em orders gera event automático
CREATE OR REPLACE FUNCTION record_order_event()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.sync_status IS DISTINCT FROM NEW.sync_status THEN
        INSERT INTO order_events
               (company_id, order_id, event_type, old_status, new_status, metadata)
        VALUES (NEW.company_id, NEW.id, 'status_changed', OLD.sync_status, NEW.sync_status,
                jsonb_build_object(
                    'erpOrderId',   NEW.erp_order_id,
                    'errorMessage', NEW.error_message
                ));
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS orders_audit ON orders;
CREATE TRIGGER orders_audit
    AFTER UPDATE ON orders
    FOR EACH ROW EXECUTE FUNCTION record_order_event();

-- ============================================================================
-- 005_webhooks.sql — Configuração de webhook por empresa (P2-E)
-- ============================================================================

CREATE TABLE IF NOT EXISTS company_webhooks (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    company_id  UUID        NOT NULL REFERENCES companies("Id") ON DELETE CASCADE,
    url         TEXT        NOT NULL,
    secret      TEXT        NOT NULL,     -- HMAC-SHA256 secret para verificar payload
    events      TEXT[]      NOT NULL DEFAULT ARRAY['order.confirmed','order.error'],
    active      BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_webhooks_company_url
    ON company_webhooks(company_id, url);

-- ============================================================================
-- 006_indexes.sql — Índices compostos para performance (P3-B)
-- ============================================================================

-- Orders: queries frequentes do relatório
CREATE INDEX IF NOT EXISTS idx_orders_company_date_status
    ON orders(company_id, created_at, sync_status);

-- Orders: soma de totalAmount por empresa (KPI)
CREATE INDEX IF NOT EXISTS idx_orders_company_total
    ON orders(company_id, total_amount) WHERE sync_status = 'synced';

-- Schema migrations lookup
CREATE INDEX IF NOT EXISTS idx_migrations_applied
    ON schema_migrations(applied_at DESC);
