-- Migration: Criar tabela de vendedores e associar à Ordens de Serviço
-- Arquivo: 009_sellers.sql

CREATE TABLE IF NOT EXISTS sellers (
    id SERIAL PRIMARY KEY,
    tenant_id UUID NOT NULL,
    erp_id INTEGER NOT NULL, -- IDFUNCIONARIO do Firebird
    name VARCHAR(200) NOT NULL,
    email VARCHAR(255),
    pin VARCHAR(255), -- passwordHash (MOB_SENHA)
    max_discount DECIMAL(10,2),
    commission DECIMAL(10,2),
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (tenant_id, erp_id)
);

CREATE INDEX IF NOT EXISTS idx_sellers_tenant ON sellers(tenant_id);

-- Adicionar campo seller_id na tabela de ordens de serviço (service_orders)
ALTER TABLE service_orders ADD COLUMN IF NOT EXISTS seller_id INTEGER;
