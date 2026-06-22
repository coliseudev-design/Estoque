# SPEC 03: Middleware (Node.js) & Worker (.NET)

## 1. Visão Geral
Este documento define as refatorações na sincronização de dados via Redis (Middleware Edge) e processamento Firebird em background (Worker .NET) para o suporte multi-filial na arquitetura Coliseu.

## 2. Worker .NET: O Elo de Sincronização e Carga
É onde a execução local das extrações ERP se consolida.

### 2.1 Uso de Variante: `appsettings.json`
Criaremos um switch `Firebird:UseMultiEmpresaVariant` como segurança para retrocompatibilidade caso precisem instanciar um cliente na versão "single-tenant antiga".

### 2.2 Rotina Carga Financeiro/Performance: `SyncCatalogJob.cs`
Estes relatórios do app são isolados do Centro de Custo e Empresa originais.
*   **Ação:** Ao invés de uma query genérica, o Worker deverá listar todas as filiais existentes no banco da VPS (via API `GET /api/branches`). O Worker então disparará loops para cada filial `forecah (var branch in branches)`, realizando consultas de Performance/Financeiro com as cláusulas `WHERE EMPRESA = X AND CENTRO = Y`.
*   O Envio ao Middleware se dará com o header `X-Branch-Id: <Branch-UUID>`.

### 2.3 Rotina Envio de Pedidos: `SyncOrdersJob.cs`
A Stored Procedure que gera o ID local `MOB_CADASTRAR_PEDIDO` recebe novos parâmetros, exigindo ser reconstruída no backend C#:
*   Ler payload validado que o Node enviou: Descobrir o ErpEmpresaId, ErpDepto e Centro no pedido importado.
*   Injetar esses 3 parâmetros nos `FbParameter` do comando `INSERT`.

> [!WARNING]
> **COMPORTAMENTO DO FIREBIRD ADO.NET:** 
> O provedor `FirebirdSql.Data.FirebirdClient` ao executar comandos com `CommandType = CommandType.Text` e `EXECUTE PROCEDURE`, **Mapeia os parâmetros por POSIÇÃO (ordem de declaração na string SQL)**, e não pelos nomes passados no `AddWithValue`. 
> 
> Durante a implementação multi-tenant, o `ColiseuSales.Configurator` sobrescreveu a SP original alterando a ordem e tipos dos parâmetros (ex: `TIPO_OPERACAO` trocou de posição com `TOTAL_PEDIDO`). Isso causou uma falha silenciosa onde o valor da venda (`1273.75`) foi inserido como Natureza da Operação (`1274`), e a operação (`7`) foi gravada como Valor do Pedido (`7.00`), resultando em pedidos ocultos no ERP. 
>
> **Correção:** A assinatura original da `MOB_CADASTRAR_PEDIDO` foi restaurada no `FirebirdBootstrapper.cs` (v2.4.6.5) mantendo a seguinte ordem estrita: `USUARIO`, `CLIENTE`, `DATA`, `HORA`, `OBSERVACAO`, `PRAZO_PEDIDO`, `TIPO_OPERACAO`, `PAGAMENTO`, `VALOR_DESCONTO`, `TOTAL_PEDIDO`, `CONDICAO_PAGAMENTO`, `DEPTO`, `EMPRESA`. Além disso, o UPDATE manual (`Fase 3`) que era feito pelo Worker foi removido, pois o `DEPTO` já é inserido nativamente pela Procedure.

### 2.4 Nova Regra: Permissões de Vendedor
O Worker deve passar a extrair tabela/view do ERP onde está a política de qual Vendedor acessa qual Filial. O payload é mandado para VPS e servirá de barreira de Listagem de Filiais pelo Middle/Identity.

## 3. Middleware Node.js: Proxy e Cache Local

### 3.1 Isolamento de Redis Namespace
O `dataStore.js` precisa passar a considerar `branchId` na nomeação das chaves quando a entidade requer separação (Estoque, Financeiro, KPIs).
*   **Shared (Escopo Master):** Clientes, Catálogo (Preços p/ Default), Condições de Pagto (`tenant:{companyId}:customers`).
*   **Isolado (Escopo Branch):** Financeiro, Performance, e o Estoque em si dentro dos produtos (`tenant:{companyId}:branch:{branchId}:financials`).

### 3.2 Validação de Identidade Cíclica
No interceptor de JWT do router (validação `requireDeviceJwt` no `auth.js`):
Extrapolar as propriedades `req.branch` retirando-as do payload token e jogando no namespace da requisição. Toda API passará a "saber" qual é o ramo atual se ele existir, aplicando esse context nas rotas `redisSet` e no PgQuery do `orders.js`.

### 3.3 Persistência de Pedido Roteado
O POST de orders continuará enviando via RabbitMQ/Redis Stream, mas registrará no banco do Middleware com o `branch_id` ativado, aproveitando-se do RLS injetado pelo DBA via comando `SET LOCAL app.current_branch_id`.
