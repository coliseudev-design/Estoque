-- ============================================================================
-- 011_branches.sql — Atualização Single-Tenant para Multi-Empresa
-- 
-- Tabela branches criada automaticamente pelo EF Core no Coliseu.Identity,
-- portanto este script lida com a injeção do conceito na tabela `orders`
-- e na política RLS, permitindo o isolamento multi-filial (Branch).
-- ============================================================================

-- Garante que se houver pedidos para a empresa e eles não têm filial,
-- eles terão que ganhar uma filial padrão (backfill feito depois na aplicação se a FK falhar, 
-- ou via default).
-- Mas primeiro criamos a coluna NULLABLE.

ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS branch_id UUID;

-- Criar a nova RLS isolando por Branch e Company
-- Antes, precisamos remover a velha e substituir.
DROP POLICY IF EXISTS tenant_isolation ON orders;

-- A política "branch_isolation" impõe:
-- 1. O pedido tem que pertencer à Company X.
-- 2. SE a requisição informou um branch via 'app.current_branch_id', o pedido tem que ser dele.
-- 3. SE a requisição NÃO informou um branch, a pessoa é Master/Identidade Geral, 
--    então ela vê os pedidos da Company inteira (todas as filiais).
DROP POLICY IF EXISTS branch_isolation ON orders;
CREATE POLICY branch_isolation ON orders
    FOR ALL
    USING (
        company_id = NULLIF(current_setting('app.current_company_id', true), '')::uuid
        AND (
            branch_id = NULLIF(current_setting('app.current_branch_id', true), '')::uuid
            OR NULLIF(current_setting('app.current_branch_id', true), '') IS NULL
        )
    );
