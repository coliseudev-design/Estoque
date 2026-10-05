-- =============================================================================
-- Coliseu Estoque — schema inicial
--
-- Toda tabela de negócio carrega tenant_id (id da empresa no Coliseu.Identity,
-- o "Serial" do painel de licenças). Toda consulta da API filtra por ele.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ── Empresas (licenças do módulo Estoque) ───────────────────────────────────
CREATE TABLE tenants (
    id                 UUID PRIMARY KEY,
    name               TEXT        NOT NULL DEFAULT '',
    -- SHA-256(UPPER(TRIM(chave))) — mesmo algoritmo do CompanyKeyGenerator do Identity.
    key_hash           TEXT        NOT NULL,
    license_checked_at TIMESTAMPTZ,
    license_valid      BOOLEAN     NOT NULL DEFAULT TRUE,
    worker_seen_at     TIMESTAMPTZ,
    worker_info        JSONB       NOT NULL DEFAULT '{}',
    settings           JSONB       NOT NULL DEFAULT '{}',
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX tenants_key_hash ON tenants (key_hash);

-- ── Usuários (operadores, supervisores, administradores) ─────────────────────
CREATE TABLE users (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id     UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    login         TEXT        NOT NULL,
    name          TEXT        NOT NULL,
    role          TEXT        NOT NULL CHECK (role IN ('operador', 'supervisor', 'admin')),
    password_hash TEXT,          -- dashboard
    pin_hash      TEXT,          -- app (PIN numérico)
    active        BOOLEAN     NOT NULL DEFAULT TRUE,
    last_login_at TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX users_tenant_login ON users (tenant_id, lower(login));

-- ── Catálogo espelhado do ERP ────────────────────────────────────────────────
CREATE TABLE products (
    tenant_id   UUID          NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    erp_id      TEXT          NOT NULL,           -- TCADPRODUTO.CODPRODUTO
    sku         TEXT,
    description TEXT          NOT NULL DEFAULT '',
    unit        TEXT,
    brand       TEXT,
    group_name  TEXT,
    stock       NUMERIC(18,4) NOT NULL DEFAULT 0,
    active      BOOLEAN       NOT NULL DEFAULT TRUE,
    updated_at  TIMESTAMPTZ   NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, erp_id)
);
CREATE INDEX products_updated ON products (tenant_id, updated_at);
CREATE INDEX products_search  ON products (tenant_id, lower(description) text_pattern_ops);

-- Um produto pode ter vários códigos (unidade, caixa, fardo).
-- factor = quantas unidades cada leitura representa (caixa com 12 → 12).
CREATE TABLE product_barcodes (
    tenant_id  UUID          NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    barcode    TEXT          NOT NULL,
    erp_id     TEXT          NOT NULL,
    factor     NUMERIC(18,4) NOT NULL DEFAULT 1 CHECK (factor > 0),
    updated_at TIMESTAMPTZ   NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, barcode)
);
CREATE INDEX product_barcodes_product ON product_barcodes (tenant_id, erp_id);
CREATE INDEX product_barcodes_updated ON product_barcodes (tenant_id, updated_at);

-- ── Documentos a conferir (notas de saída, pedidos) ─────────────────────────
--
-- Ciclo de vida:
--   AGUARDANDO ──claim──► EM_CONFERENCIA ──finalizar──► CONCLUIDO
--                              │  ▲                        ▲
--                   divergência│  │recontagem              │aprovar
--                              ▼  │                        │
--                          DIVERGENTE ──limite de recontagens──► AGUARDANDO_APROVACAO
--   (qualquer estado não concluído) ──ERP cancelou──► CANCELADO
CREATE TABLE documents (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id        UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    source           TEXT        NOT NULL,           -- NFS (nota de saída), PED (pedido)
    erp_key          TEXT        NOT NULL,           -- TBNOTASSAIDA.CHAVE
    number           TEXT,
    series           TEXT,
    movement_type    INTEGER,                        -- CODTM
    issued_at        TIMESTAMPTZ,
    customer_code    TEXT,
    customer_name    TEXT,
    seller_name      TEXT,
    branch_code      INTEGER,
    status           TEXT        NOT NULL DEFAULT 'AGUARDANDO'
                     CHECK (status IN ('AGUARDANDO','EM_CONFERENCIA','DIVERGENTE',
                                       'AGUARDANDO_APROVACAO','CONCLUIDO','CANCELADO')),
    priority         INTEGER     NOT NULL DEFAULT 0,
    round            INTEGER     NOT NULL DEFAULT 0, -- 0 = contagem; 1+ = recontagens
    locked_by        UUID REFERENCES users(id),
    locked_device    TEXT,
    lock_expires_at  TIMESTAMPTZ,
    started_by       UUID REFERENCES users(id),
    started_at       TIMESTAMPTZ,
    finished_by      UUID REFERENCES users(id),
    finished_at      TIMESTAMPTZ,
    approved_by      UUID REFERENCES users(id),
    approved_at      TIMESTAMPTZ,
    justification    TEXT,
    has_divergence   BOOLEAN     NOT NULL DEFAULT FALSE,
    erp_hash         TEXT,                           -- detecta alteração do documento no ERP
    erp_changed      BOOLEAN     NOT NULL DEFAULT FALSE,
    erp_cancelled    BOOLEAN     NOT NULL DEFAULT FALSE,
    writeback_status TEXT        NOT NULL DEFAULT 'NAO_APLICAVEL'
                     CHECK (writeback_status IN ('NAO_APLICAVEL','PENDENTE','GRAVADO','ERRO')),
    writeback_at     TIMESTAMPTZ,
    writeback_error  TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (tenant_id, source, erp_key)
);
CREATE INDEX documents_queue     ON documents (tenant_id, status, priority DESC, issued_at);
CREATE INDEX documents_issued    ON documents (tenant_id, issued_at DESC);
CREATE INDEX documents_writeback ON documents (tenant_id, writeback_status) WHERE writeback_status = 'PENDENTE';

CREATE TABLE document_items (
    document_id    UUID          NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    seq            INTEGER       NOT NULL,           -- sequência no ERP; itens extras ≥ 100000
    tenant_id      UUID          NOT NULL,
    product_erp_id TEXT          NOT NULL,
    description    TEXT          NOT NULL DEFAULT '',
    unit           TEXT,
    expected_qty   NUMERIC(18,4) NOT NULL,
    counted_qty    NUMERIC(18,4),                    -- NULL até a primeira finalização
    result         TEXT          NOT NULL DEFAULT 'PENDENTE'
                   CHECK (result IN ('PENDENTE','OK','FALTA','SOBRA')),
    is_extra       BOOLEAN       NOT NULL DEFAULT FALSE, -- produto bipado que não está no documento
    counted_round  INTEGER,
    PRIMARY KEY (document_id, seq)
);
CREATE INDEX document_items_product ON document_items (document_id, product_erp_id);

-- Cada leitura é um evento imutável. O id é gerado no cliente (UUID) para que
-- o reenvio de uma fila offline nunca duplique a contagem.
CREATE TABLE scan_events (
    id             UUID PRIMARY KEY,
    tenant_id      UUID          NOT NULL,
    document_id    UUID          NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    round          INTEGER       NOT NULL,
    product_erp_id TEXT,                              -- NULL = código não reconhecido
    barcode        TEXT,
    qty            NUMERIC(18,4) NOT NULL CHECK (qty <> 0),
    user_id        UUID REFERENCES users(id),
    device_id      TEXT,
    origin         TEXT          NOT NULL DEFAULT 'manual'
                   CHECK (origin IN ('camera','coletor','teclado','manual','web')),
    scanned_at     TIMESTAMPTZ   NOT NULL,
    received_at    TIMESTAMPTZ   NOT NULL DEFAULT now(),
    voided         BOOLEAN       NOT NULL DEFAULT FALSE,
    voided_by      UUID REFERENCES users(id)
);
CREATE INDEX scan_events_doc_round ON scan_events (document_id, round) WHERE NOT voided;
CREATE INDEX scan_events_user_day  ON scan_events (tenant_id, user_id, scanned_at);

-- ── Auditoria ────────────────────────────────────────────────────────────────
CREATE TABLE audit_log (
    id          BIGSERIAL PRIMARY KEY,
    tenant_id   UUID        NOT NULL,
    document_id UUID,
    user_id     UUID,
    action      TEXT        NOT NULL,
    details     JSONB       NOT NULL DEFAULT '{}',
    at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX audit_log_tenant_at ON audit_log (tenant_id, at DESC);
CREATE INDEX audit_log_document  ON audit_log (document_id, at) WHERE document_id IS NOT NULL;

-- ── Estado do sincronismo por entidade (exibido no painel) ──────────────────
CREATE TABLE sync_state (
    tenant_id UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    entity    TEXT        NOT NULL,
    last_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    rows      INTEGER     NOT NULL DEFAULT 0,
    PRIMARY KEY (tenant_id, entity)
);
