-- Pedido de venda → conferência → faturamento.
--
-- No Siscom o pedido (série PE, CODTM 99) e a nota (série 55) ficam em TBNOTASSAIDA;
-- a nota aponta para o pedido em NUMPEDIDO. O pedido é conferido ANTES de faturar;
-- quando a NF sai, o Worker informa o número dela no próprio pedido.

ALTER TABLE documents ADD COLUMN invoice_number TEXT;   -- PED: NF emitida a partir deste pedido
ALTER TABLE documents ADD COLUMN order_number   TEXT;   -- NFS: pedido de origem
ALTER TABLE documents ADD COLUMN invoiced_at    TIMESTAMPTZ;

CREATE INDEX documents_order_number ON documents (tenant_id, order_number) WHERE order_number IS NOT NULL;
