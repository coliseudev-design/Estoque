-- Migration: Criar tabelas de Veículos, Ordens de Serviço, Itens, Fotos e Checklist
-- Arquivo: 006_service_orders.sql

-- 1. Tabela de Veículos (se já não criada)
CREATE TABLE IF NOT EXISTS vehicles (
    id SERIAL PRIMARY KEY,
    tenant_id UUID NOT NULL,
    id_cliente INTEGER, -- IDCLIENTE do Firebird (tabela customers)
    id_veiculo INTEGER, -- ID do veículo no ERP
    brand VARCHAR(100),
    model VARCHAR(100),
    plate VARCHAR(20) NOT NULL,
    ano_fabrica INTEGER,
    ano_modelo INTEGER,
    cor VARCHAR(50),
    obs TEXT,
    numero VARCHAR(50),
    numero_chassi VARCHAR(100),
    id_seguradora INTEGER,
    status INTEGER,
    numero_1 VARCHAR(50),
    numero_2 VARCHAR(50),
    combustivel VARCHAR(50),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (tenant_id, plate)
);

CREATE INDEX IF NOT EXISTS idx_vehicles_tenant_plate ON vehicles(tenant_id, plate);

-- 2. Tabela de Ordens de Serviço (Service Orders)
CREATE TABLE IF NOT EXISTS service_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tenant_id UUID NOT NULL,
    quote_id UUID REFERENCES quotes(id) ON DELETE SET NULL,
    device_id VARCHAR(100) NOT NULL,
    plate VARCHAR(20) NOT NULL,
    customer_id INTEGER, -- ERP ID do cliente
    customer_name VARCHAR(150),
    customer_phone VARCHAR(20),
    status VARCHAR(50) NOT NULL DEFAULT 'OPEN', -- OPEN, IN_PROGRESS, COMPLETED, CANCELLED
    total_amount DECIMAL(12,2) NOT NULL DEFAULT 0,
    observation TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_service_orders_tenant_status ON service_orders(tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_service_orders_plate ON service_orders(plate);

-- 3. Tabela de Itens de Ordens de Serviço
CREATE TABLE IF NOT EXISTS service_order_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    service_order_id UUID NOT NULL REFERENCES service_orders(id) ON DELETE CASCADE,
    product_code VARCHAR(50) NOT NULL,
    product_description VARCHAR(255) NOT NULL,
    quantity DECIMAL(10,3) NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    total_price DECIMAL(10,2) NOT NULL,
    item_type VARCHAR(20) NOT NULL DEFAULT 'PART', -- PART, SERVICE
    technician_id INTEGER, -- ID do técnico/mecânico no ERP
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Tabela de Fotos de Ordens de Serviço
CREATE TABLE IF NOT EXISTS service_order_photos (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    service_order_id UUID NOT NULL REFERENCES service_orders(id) ON DELETE CASCADE,
    photo_url VARCHAR(500) NOT NULL,
    photo_type VARCHAR(50), -- ODOMETER, DAMAGE, GENERAL
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Tabela de Checklist de Ordens de Serviço
CREATE TABLE IF NOT EXISTS service_order_checklist (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    service_order_id UUID NOT NULL REFERENCES service_orders(id) ON DELETE CASCADE,
    item_name VARCHAR(150) NOT NULL,
    status VARCHAR(50) NOT NULL, -- e.g. OK, WARN, BAD
    observation TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
