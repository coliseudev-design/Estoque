-- Migration: Criar tabela de clientes pendentes de integração (criados offline no mobile)
-- Arquivo: 007_pending_customers.sql

CREATE TABLE IF NOT EXISTS pending_customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL,
    local_id VARCHAR(100) NOT NULL, -- ID temporário do lado do Flutter (local_...)
    name VARCHAR(200) NOT NULL,
    fantasy_name VARCHAR(200),
    cpf_cnpj VARCHAR(20),
    phone VARCHAR(25),
    phone2 VARCHAR(25),
    email VARCHAR(150),
    city VARCHAR(100),
    address VARCHAR(255),
    street VARCHAR(150),
    number VARCHAR(20),
    complement VARCHAR(100),
    neighborhood VARCHAR(100),
    zip VARCHAR(20),
    state VARCHAR(20),
    status VARCHAR(50) NOT NULL DEFAULT 'PENDING', -- PENDING, SYNCHRONIZED, ERROR
    erp_id INTEGER, -- Preenchido após integração com sucesso no ERP
    error_message TEXT, -- Preenchido se falhar a integração
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (tenant_id, local_id)
);

CREATE INDEX IF NOT EXISTS idx_pending_customers_tenant ON pending_customers(tenant_id);
CREATE INDEX IF NOT EXISTS idx_pending_customers_status ON pending_customers(tenant_id, status);
