-- Migration: Criar tabela de filiais sincronizadas do Identity Server
-- Permite ao app mobile obter a lista de filiais da empresa.

CREATE TABLE IF NOT EXISTS dash_filiais (
    id SERIAL PRIMARY KEY,
    tenant_id UUID NOT NULL,
    empresa_erp INT NOT NULL DEFAULT 1,
    depto_id INT NOT NULL,
    centro_custo INT,
    nome VARCHAR(200) NOT NULL,
    documento VARCHAR(20),
    is_default BOOLEAN NOT NULL DEFAULT false,
    ativo BOOLEAN NOT NULL DEFAULT true,
    sincronizado_em TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (tenant_id, depto_id)
);

CREATE INDEX IF NOT EXISTS idx_dash_filiais_tenant ON dash_filiais(tenant_id);
