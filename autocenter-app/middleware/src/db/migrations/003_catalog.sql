CREATE TABLE IF NOT EXISTS catalog (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL,
  erp_id INTEGER NOT NULL,
  name VARCHAR(255) NOT NULL,
  category VARCHAR(100),
  price DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
  brand VARCHAR(100),
  code VARCHAR(50),
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(tenant_id, erp_id)
);

CREATE INDEX IF NOT EXISTS idx_catalog_tenant_category ON catalog(tenant_id, category);
