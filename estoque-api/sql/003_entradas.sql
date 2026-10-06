-- Recebimento: conferência cega de notas de ENTRADA (compra) a partir do XML da NF-e.
--
-- A nota de entrada não vem do Worker: o supervisor importa o XML (ou bipa o DANFE e
-- importa o XML em seguida). Ela vira um documento source = 'NFE' e segue exatamente
-- o mesmo ciclo da conferência cega das saídas (contagem → recontagem → aprovação).
--
--   erp_key       = chave de acesso (44 dígitos)
--   customer_*    = emitente (fornecedor)
--   order_number  = pedido de compra referenciado no XML (xPed), quando houver

ALTER TABLE documents ADD COLUMN meta        JSONB       NOT NULL DEFAULT '{}';
ALTER TABLE documents ADD COLUMN imported_by UUID REFERENCES users(id);
ALTER TABLE documents ADD COLUMN imported_at TIMESTAMPTZ;

-- Dados do item vindos do XML: código e unidade do fornecedor, GTIN, lote/validade.
ALTER TABLE document_items ADD COLUMN meta JSONB NOT NULL DEFAULT '{}';

CREATE INDEX documents_flow ON documents (tenant_id, (source = 'NFE'), status);

-- Códigos válidos só dentro de um documento (GTIN do XML, código do fornecedor).
-- Têm precedência sobre product_barcodes: na entrada, o que vale é a embalagem da nota.
CREATE TABLE document_barcodes (
    document_id    UUID          NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    barcode        TEXT          NOT NULL,
    product_erp_id TEXT          NOT NULL,
    factor         NUMERIC(18,4) NOT NULL DEFAULT 1 CHECK (factor > 0),
    PRIMARY KEY (document_id, barcode)
);

-- De-para fornecedor → produto: aprendido quando o supervisor vincula um item sem
-- cadastro. A próxima nota do mesmo fornecedor já chega vinculada.
CREATE TABLE supplier_products (
    tenant_id      UUID        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    supplier_cnpj  TEXT        NOT NULL,
    supplier_code  TEXT        NOT NULL,
    product_erp_id TEXT        NOT NULL,
    updated_by     UUID REFERENCES users(id),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, supplier_cnpj, supplier_code)
);
