-- DDL 002 — Tabela de controle de idempotência para pedidos móveis
-- Executar no banco PIVETA.FDB via FlameRobin ou isql

-- Registra os UUIDs dos pedidos recebidos do app para evitar duplicatas
CREATE TABLE SYNC_ORDERS (
    ID            VARCHAR(36)  NOT NULL,   -- UUID v4 gerado pelo app
    ID_PEDIDO_ERP INTEGER,                -- ID_PEDIDO retornado por MOB_CADASTRAR_PEDIDO
    SELLER_ID     VARCHAR(50),            -- ID do funcionário/vendedor
    CUSTOMER_ID   INTEGER,                -- ID_CLIENTE
    -- STATUS do fluxo: received → processing → integrated | error
    STATUS        VARCHAR(20)  NOT NULL DEFAULT 'received',
    ERROR_MSG     VARCHAR(500),           -- Mensagem de erro se STATUS = 'error'
    RECEIVED_AT   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INTEGRATED_AT TIMESTAMP,              -- Preenchido quando STATUS = 'integrated'
    CONSTRAINT PK_SYNC_ORDERS PRIMARY KEY (ID)
);

-- Índice para checagem de idempotência (usada no middleware a cada recebimento)
CREATE INDEX IDX_SYNC_ORDERS_ID_PEDIDO ON SYNC_ORDERS (ID_PEDIDO_ERP);
CREATE INDEX IDX_SYNC_ORDERS_RECEIVED  ON SYNC_ORDERS (RECEIVED_AT);
-- Índice para consultas de relatório por vendedor e por status
CREATE INDEX IDX_SYNC_ORDERS_SELLER    ON SYNC_ORDERS (SELLER_ID);
CREATE INDEX IDX_SYNC_ORDERS_STATUS    ON SYNC_ORDERS (STATUS);

-- ----------------------------------------------------------------
-- PROCEDURE: SP_PURGE_OLD_SYNC_ORDERS
-- Remove registros finalizados (integrated/error) com mais de 90
-- dias para evitar crescimento ilimitado em produção.
-- Executar periodicamente via job do Firebird ou tarefa agendada:
--   EXECUTE PROCEDURE SP_PURGE_OLD_SYNC_ORDERS;
-- ----------------------------------------------------------------
SET TERM ^ ;

CREATE PROCEDURE SP_PURGE_OLD_SYNC_ORDERS
RETURNS (DELETED_COUNT INTEGER)
AS
BEGIN
    DELETE FROM SYNC_ORDERS
    WHERE STATUS IN ('integrated', 'error')
      AND RECEIVED_AT < DATEADD(-90 DAY TO CURRENT_TIMESTAMP);

    DELETED_COUNT = ROW_COUNT;

    SUSPEND;
END^

SET TERM ; ^
