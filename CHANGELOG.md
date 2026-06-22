# Changelog — Coliseu Sales

Histórico de atualizações e alterações do projeto.

## [2.5.38] — 2026-05-21

### Features & Refatoração (Sincronização Multi-Filial)
- **C# Worker**:
  * **Sincronização de Catálogo por Filial (`SyncCatalogJob.cs`)**: Refatorado para iterar em todas as filiais configuradas no Identity. A query SQL foi ajustada com `LEFT JOIN PRODUTO_DEPTOS` filtrando pelo `ID_DEPTO` correspondente a cada filial para obter o saldo de estoque correto de cada loja.
  * **Filtro de Financeiro por Filial (`SyncCatalogJob.cs`)**: Ajustado para filtrar os títulos financeiros em aberto (`CONTAS`) pelo departamento (`ID_DEPTO`) de cada filial individualmente e enviar o `branchId` correto para a VPS.
  * **Prevenção de Duplicidade de Notificação**: Lógicas de push para o *Atendente do Futuro* (tanto no catálogo quanto no financeiro) configuradas para rodar apenas no primeiro loop (filial padrão), economizando chamadas externas desnecessárias.
  * **Rankings de Vendas por Filial (`SyncSalesRankingsJob.cs`)**: Refatorado o agrupamento de estatísticas e metas dos vendedores segmentando os itens por `branchId` antes de enviar à API da VPS.
  * **Validação de Departamentos**: Adicionado skip/ignorar filiais com `ErpDeptoPadrao <= 0` (não configuradas) para evitar erros de consistência ou loops desnecessários.
  * **Compatibilidade**: Correções de compilação em `OrderEndpoints.cs` na instanciação do record de ordens pendentes.

- **NodeJS Middleware**:
  * **Otimização de Preços Globais (`dataStore.js`)**: Removidos `priceTables` e `productPrices` do conjunto de entidades isoladas por filial (`BRANCH_SCOPED_ENTITIES`). Agora, as tabelas de preços e os preços de produtos são compartilhados globalmente no Redis para todo o tenant, corrigindo a ausência de tabelas de preços nas filiais secundárias 2 e 3 e poupando recursos.

### Build & Deploy
- Atualizada a versão do Configurator para `2.5.38`.
- Publicado com sucesso o executável unificado `ColiseuSales_Configurator_2.5.38.exe` compilando Worker + Configurator.
- Transferidos e commitados todos os arquivos modificados para o repositório original do GitHub Desktop em `C:\Users\rober\OneDrive\Documentos\GitHub\ColiseuSales`.
