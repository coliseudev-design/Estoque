-- Migration: Adicionar suporte a filiais e departamentos (depto_id) na tabela de orçamentos (quotes)
ALTER TABLE quotes ADD COLUMN IF NOT EXISTS branch_id VARCHAR(100);
ALTER TABLE quotes ADD COLUMN IF NOT EXISTS depto_id INT;
ALTER TABLE quotes ADD COLUMN IF NOT EXISTS empresa_erp INT;
ALTER TABLE quotes ADD COLUMN IF NOT EXISTS centro_custo INT;

CREATE INDEX IF NOT EXISTS idx_quotes_branch_id ON quotes(branch_id);
