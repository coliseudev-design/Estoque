-- Schema do PostgreSQL para AutoCenter Middleware
-- Executar isto em: autocenter_db

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Tabela de Orçamentos
CREATE TABLE IF NOT EXISTS quotes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL, -- Referência ao CompanyId do Coliseu.Identity
    device_id VARCHAR(100) NOT NULL, -- Dispositivo que criou o orçamento
    plate VARCHAR(10) NOT NULL,
    vehicle_info JSONB, -- Info da APIBrasil cacheada no momento do orcamento
    customer_name VARCHAR(150),
    customer_phone VARCHAR(20),
    status VARCHAR(50) NOT NULL DEFAULT 'DRAFT', -- DRAFT, PENDING_APPROVAL, APPROVED, REJECTED, INTEGRATED
    total_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_quotes_tenant_status ON quotes(tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_quotes_plate ON quotes(plate);

-- Tabela de Itens de Orçamentos
CREATE TABLE IF NOT EXISTS quote_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    quote_id UUID REFERENCES quotes(id) ON DELETE CASCADE,
    product_code VARCHAR(50) NOT NULL,
    product_description VARCHAR(255) NOT NULL,
    quantity DECIMAL(10,3) NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    total_price DECIMAL(10,2) NOT NULL,
    item_type VARCHAR(20) NOT NULL DEFAULT 'PART', -- PART, SERVICE
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Tabela de Fotos Associadas
CREATE TABLE IF NOT EXISTS quote_photos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    quote_id UUID REFERENCES quotes(id) ON DELETE CASCADE,
    photo_url VARCHAR(500) NOT NULL,
    photo_type VARCHAR(50), -- ODOMETER, DAMAGE, GENERAL
    created_at TIMESTAMPTZ DEFAULT NOW()
);
