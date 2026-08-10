-- Adicionar tabela de clientes sincronizados do Firebird (ERP)
-- Permitir que o app mobile funcione offline com dados de clientes reais

CREATE TABLE IF NOT EXISTS customers (
    id            SERIAL PRIMARY KEY,
    tenant_id     UUID          NOT NULL,
    erp_id        INTEGER       NOT NULL, -- IDCLIENTE do Firebird
    name          VARCHAR(200)  NOT NULL,
    fantasy_name  VARCHAR(200),
    cpf_cnpj      VARCHAR(20),
    phone         VARCHAR(25),
    phone2        VARCHAR(25),
    email         VARCHAR(150),
    city          VARCHAR(100),
    address       VARCHAR(255),
    active        BOOLEAN       NOT NULL DEFAULT true,
    synced_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- Índice único por tenant + ERP ID (evita duplicatas em upsert)
CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_tenant_erpid
    ON customers(tenant_id, erp_id);

CREATE INDEX IF NOT EXISTS idx_customers_tenant_name
    ON customers(tenant_id, LOWER(name));

CREATE INDEX IF NOT EXISTS idx_customers_tenant_cpfcnpj
    ON customers(tenant_id, cpf_cnpj);
