-- Migration: Criar tabelas de espécie de pagamento, condição de pagamento, naturezas de operação e associar às ordens de serviço e orçamentos
-- Arquivo: 010_erp_configurations.sql

CREATE TABLE IF NOT EXISTS payment_species (
    id SERIAL PRIMARY KEY,
    tenant_id UUID NOT NULL,
    erp_id INTEGER NOT NULL,
    description VARCHAR(100) NOT NULL,
    tipo VARCHAR(50),
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (tenant_id, erp_id)
);

CREATE INDEX IF NOT EXISTS idx_payment_species_tenant ON payment_species(tenant_id);

CREATE TABLE IF NOT EXISTS payment_conditions (
    id VARCHAR(50) PRIMARY KEY, -- ID composto: ID_FORMA_ID_ESPECIE
    tenant_id UUID NOT NULL,
    especie_id INTEGER,
    forma_id INTEGER,
    descricao VARCHAR(100) NOT NULL,
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payment_conditions_tenant ON payment_conditions(tenant_id);

CREATE TABLE IF NOT EXISTS naturezas_operacao (
    id SERIAL PRIMARY KEY,
    tenant_id UUID NOT NULL,
    erp_id INTEGER NOT NULL,
    descricao VARCHAR(150) NOT NULL,
    descricao_nota VARCHAR(150),
    codigo_fiscal VARCHAR(50),
    es INTEGER,
    processo INTEGER,
    tipo INTEGER,
    mob_ordem INTEGER,
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (tenant_id, erp_id)
);

CREATE INDEX IF NOT EXISTS idx_naturezas_operacao_tenant ON naturezas_operacao(tenant_id);

-- Adicionar colunas na tabela de ordens de serviço
ALTER TABLE service_orders ADD COLUMN IF NOT EXISTS natureza_id VARCHAR(50);
ALTER TABLE service_orders ADD COLUMN IF NOT EXISTS payment_condition_id VARCHAR(50);
ALTER TABLE service_orders ADD COLUMN IF NOT EXISTS payment_species_id VARCHAR(50);

-- Adicionar colunas na tabela de orçamentos (quotes)
ALTER TABLE quotes ADD COLUMN IF NOT EXISTS natureza_id VARCHAR(50);
ALTER TABLE quotes ADD COLUMN IF NOT EXISTS payment_condition_id VARCHAR(50);
ALTER TABLE quotes ADD COLUMN IF NOT EXISTS payment_species_id VARCHAR(50);
