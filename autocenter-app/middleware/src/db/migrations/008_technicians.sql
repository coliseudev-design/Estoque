-- Migration: Criar tabela de técnicos/vendedores sincronizados
-- Arquivo: 008_technicians.sql

CREATE TABLE IF NOT EXISTS technicians (
    id SERIAL PRIMARY KEY,
    tenant_id UUID NOT NULL,
    erp_id INTEGER NOT NULL, -- IDFUNCIONARIO do Firebird
    name VARCHAR(200) NOT NULL,
    active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (tenant_id, erp_id)
);

CREATE INDEX IF NOT EXISTS idx_technicians_tenant ON technicians(tenant_id);
