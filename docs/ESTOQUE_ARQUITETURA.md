# Coliseu Estoque — Arquitetura

Conferência cega e separação para expedição, integrada ao ERP Siscom (Firebird),
operada pelo **app** (celular/coletor) e pelo **dashboard** (navegador) com as mesmas regras.

```
 ┌─────────────── cliente (loja/CD) ───────────────┐          ┌──────────── nuvem ────────────┐
 │                                                  │          │                               │
 │  Firebird (Siscom) ◄─SELECT── ColiseuWorkervett ─┼─HTTPS───►│  estoque-api (Node 20)        │
 │        ▲               (canal Estoque,           │          │   ├─ regras da conferência    │
 │        └─ COL_EST_* ── licença própria)          │          │   ├─ PostgreSQL 16            │
 │          (opcional)                              │          │   ├─ SSE (LISTEN/NOTIFY)      │
 │                                                  │          │   └─ serve o dashboard/       │
 │  App Flutter (coletor/celular) ──────────────────┼─HTTPS───►│                               │
 │   └─ SQLite: fila offline + catálogo             │          │  Coliseu.Identity             │
 └──────────────────────────────────────────────────┘          │   ├─ licença do módulo        │
                                                               │   └─ ativação de aparelhos    │
                         Navegador (dashboard) ───────HTTPS───►└───────────────────────────────┘
```

## Pastas

| Pasta | O quê |
|---|---|
| `estoque-api/` | API central: regras, auditoria, tempo real. Única dona das regras de negócio. |
| `dashboard/` | SPA estática servida pela própria API (mesmo domínio, sem CORS). |
| `app/` | App Flutter offline-first (Android/iOS, coletores Zebra/Honeywell). |
| `scripts/firebird/` | DDL das tabelas `COL_EST_*` (retorno ao ERP) e diagnóstico do VetMatriz. |
| `../workerVet/` | Worker Windows — ganhou o canal Estoque (`docs/ESTOQUE.md` lá). |
| `Coliseu.Identity/` | Painel de licenças — slug `coliseu-estoque` registrado. |

As pastas `middleware/`, `api/`, `mobile/`, `coliseu-speed-web/`, `worker/` são do
**Coliseu Speed (vendas)** e não fazem parte do Estoque.

## Decisões

**Só o Worker fala com o Firebird.** O ERP não fica exposto na internet; app e
dashboard nunca abrem conexão com o banco do cliente.

**Uma API, dois clientes.** App e dashboard usam os mesmos endpoints `/v1/*`. O
perfil do usuário define o que volta: operador recebe a lista *cega* (nunca a
quantidade esperada); supervisor/admin recebem esperado × contado.

**Leituras são eventos imutáveis** (`scan_events`, id UUID gerado no cliente). A
contagem é a soma dos eventos válidos da rodada. Isso dá: idempotência no reenvio
offline, estorno auditável, e nenhum conflito "último que salvou vence".

**Concorrência no banco, não na aplicação.** Toda transição faz `SELECT … FOR UPDATE`
no documento. Reserva (lock) com expiração renovada a cada leitura.

**Regras da conferência** (puras, testadas em `estoque-api/tests/`):
1. compara por produto (a nota pode repetir o produto em várias linhas);
2. produto fora do documento vira item extra (SOBRA);
3. recontagem só do que divergiu; o que bateu fica travado;
4. esgotadas as recontagens (`maxRecounts`), vai para aprovação do supervisor,
   com justificativa obrigatória (configurável).

**Tempo real com `LISTEN/NOTIFY` + SSE.** Funciona com várias instâncias da API e
atravessa nginx/Traefik sem configuração de WebSocket. O payload leva só ids — o
cliente busca o detalhe pela API, respeitando o perfil.

**Licença igual ao Vision.** Worker: `X-Internal-Key` (chave do módulo) + `X-Tenant-Id`,
validados em `/internal/companies/{id}/modules/{slug}/validate-key`, com cache de
5 min e carência de 24 h se o Identity cair (negativa explícita corta na hora).
App: ativação do aparelho no Identity (`moduleSlug: coliseu-estoque`) → conta no limite de
dispositivos do módulo. Dashboard: Serial + chave do módulo + usuário/senha.

**Retorno ao ERP opcional e confinado.** Desligado por padrão; quando ligado, grava
apenas em `COL_EST_CONFERENCIA(_ITEM)` (DDL roda o DBA). O `FirebirdService` do
Worker continua sem nenhum método de escrita.

## Entradas × saídas

O painel separa os dois fluxos; a conferência cega é a mesma.

| | Entradas (recebimento) | Saídas (expedição) |
|---|---|---|
| Origem | XML da NF-e importado no painel (`POST /v1/entries/import`) | Worker (`/internal/v1/sync/documents`) |
| `documents.source` | `NFE` (`erp_key` = chave de acesso) | `PED` / `NFS` |
| Leitor | DANFE do fornecedor → nota importada; se não existir, oferece importar o XML (validando que é a mesma chave) | Pedido, NF ou DANFE próprio |
| Retorno ao ERP | não grava (entrada continua manual no ERP) | `COL_EST_*` quando ligado |

**Códigos da nota** (`document_barcodes`) valem só dentro do documento e têm precedência
sobre o cadastro: caixa com GTIN próprio (`cEAN`) e unidade com outro (`cEANTrib`) é
conferida em unidades — bipar a caixa soma o fator `qTrib ÷ qCom`. O código do fornecedor
(`cProd`) também identifica o item (itens sem GTIN).

**Vínculo de produto**: item sem GTIN no cadastro entra como `NFE:<cProd>`. O supervisor
vincula ao produto do ERP e o de-para fica em `supplier_products` — a próxima nota do
mesmo fornecedor já chega vinculada.

**Críticas** (`domain/nfe.js` → `entryCritiques`, `domain/alerts.js` → `documentAlerts`):
nota destinada a outro CNPJ, sem protocolo/não autorizada, homologação, emissão antiga,
sem pedido de compra, item sem vínculo, sem GTIN, unidade diferente do cadastro, lote
vencido / validade curta; e na operação: SLA estourado, conferência abandonada, ERP alterou,
faturado antes de conferir, erro no retorno ao ERP, divergência pendente. A regra de
"precisa de atenção" também existe em SQL (`ATTENTION_SQL`) para filtros e contadores.
Configurações novas: `companyCnpj`, `outboundSlaHours`, `expiryAlertDays`, `entryOldDays`.

## Pendências conhecidas

- **Diagnóstico do VetMatriz** (`scripts/diagnostico_conferencia_vetmatriz.sql`):
  confirmar se o Siscom já usa `TBCONFCEGA`/`TBPICKINGUP`. Se sim, o retorno ao ERP
  passa a gravar nelas (mudança só no `EstoqueErpWriter`).
- Conferir **antes** do faturamento depende de saber como o pedido aparece no Siscom
  (`CODTM` 99 / `NUMNOTA = 0`?) — hoje é configurável (`TiposMovimento`, `IncluirSemNumero`).
- Slug do módulo em produção: confirmar no painel; confirmado `coliseu-estoque` (a API lê `ESTOQUE_MODULE_SLUG`).
- Configurador do Worker: os campos do Estoque ainda não têm tela — editar `appsettings.json`.
- Entradas: cruzar a nota com o **pedido de compra do ERP** (quantidade/preço) depende de o Worker
  sincronizar os pedidos de compra; hoje só se critica a ausência de `xPed`.
- App Flutter: ainda mostra notas de entrada como "Pedido" (`models.dart` → `title`); falta o filtro `flow`.

## Subir local

```bash
cp estoque-api/.env.example estoque-api/.env      # preencha os segredos
docker compose -f docker-compose.estoque.yml up -d --build
# dashboard em http://localhost:3100 — primeiro acesso cria o administrador
```

Worker de teste com a base VetMatriz: `workerVet/config/appsettings.estoque-vetmatriz.json`.
