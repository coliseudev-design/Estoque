# SPEC 01: DBA PostgreSQL (Estratégia de Banco e Isolamento)

## 1. Visão Geral
Esta especificação define as mudanças necessárias no banco de dados PostgreSQL (`ColiseuSpeed` / Identity) para suportar múltiplas filiais (Branches) sob um único Tenant (Company), garantindo a imposição de regras rígidas de segurança em nível de linha (RLS - Row Level Security).

## 2. Entidades & Schema

### 2.1 Tabela `branches`
Responsável por espelhar os parâmetros de configuração ERP de cada filial.

**Estrutura esperada:**
*   `Id` (UUID, Primary Key)
*   `CompanyId` (UUID, Foreign Key -> `companies.Id`, Delete Cascade)
*   `Name` (Varchar 100) - Nome fantasia da filial
*   `Cnpj` (Varchar 20, Nullable)
*   `ErpEmpresaId` (Int) - Correspondente ao campo ID_EMPRESA do ERP
*   `ErpDeptoPadrao` (Int) - Correspondente ao ID de Departamento para cálculo de Estoque
*   `ErpCentroPadrao` (Int) - Correspondente ao ID de Centro de Custo em Financeiro
*   `IsDefault` (Booleano) - Se é a filial matriz/principal assumida quando a empresa é criada
*   `Status` (Int) - 0 (Ativa), 1 (Inativa)

**Constraints:**
*   `idx_branches_company_erp`: Unicidade na combinação `(CompanyId, ErpEmpresaId)`.
*   Apenas UMA filial pode ser `IsDefault = TRUE` por `CompanyId`.

### 2.2 Tabela `orders`
A tabela central de pedidos consolidados que já possui `company_id`.

**Alterações:**
*   Adicionar coluna `branch_id` (UUID, Nullable por design temporário para backfill, depois obrigatório na aplicação).
*   Constraint: FK -> `branches.Id`.

## 3. Backfill Strategy
Como o banco já possui dados em produção, será necessário um script de Migration de duas fases:
1.  **Fase de Criação:** Cria a tabela `branches` e cria 1 registro de Branch padrão (`IsDefault = TRUE`) para cada `Company` existente.
2.  **Fase de Update:** Mudar todos os `orders` existentes de cada `Company` para o `branch_id` da filial de backfill correspondente criada no passo anterior.

## 4. Row Level Security (RLS)
Já existe uma RLS para multi-tenant. Agora, estenderemos para a camada de filial, isolando os Pedidos:

```sql
CREATE POLICY branch_isolation ON orders
    FOR ALL
    USING (
        company_id = current_setting('app.current_company_id')::uuid
        AND (
            branch_id = current_setting('app.current_branch_id', true)::uuid
            OR current_setting('app.current_branch_id', true) IS NULL
        )
    );
```
*A flag `true` no current_setting permite que o setting seja omitido temporariamente ou lido vazio no caso de managers da Matriz consultando todos os pedidos.*

## 5. Próximos Passos (Checklist do Agente)
1. Criar o SQL de migração.
2. Validar o comportamento de RLS em ambiente local.
