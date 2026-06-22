-- ============================================================================
-- 008_orders_payload.sql — Adiciona coluna payload JSONB na tabela orders.
--
-- PROBLEMA: O Worker (SyncOrdersJob) precisa do payload completo do pedido
-- (customerId, sellerId, items, paymentSpeciesId, etc.) para chamar
-- MOB_CADASTRAR_PEDIDO no Firebird.
-- Antes desta migration, apenas dados de resumo eram salvos (customer_name,
-- seller_name, total_amount), tornando impossível o Worker processar o pedido.
-- ============================================================================

ALTER TABLE orders ADD COLUMN IF NOT EXISTS payload JSONB;
