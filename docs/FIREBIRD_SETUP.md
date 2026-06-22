# Coliseu Sales — Guia de Setup e Operação

Guia completo para configurar o ambiente de produção do sistema Coliseu Sales Force.

---

## Arquitetura

```
[Firebird ERP local]
        │
        │  lê dados
        ▼
[Worker .NET 8]  ──── push via HTTP ───▶  [VPS Node.js API]
 ColiseuSales.Worker                       middleware/
                                                │
                                           recebe push de catálogo,
                                           pedidos e confirmações
                                                │
                                           ◀── sync pull ──  [App Flutter]
```

| Componente | Linguagem | Função |
|---|---|---|
| `worker/` | .NET 8 (Windows Service) | Lê Firebird → envia para VPS |
| `middleware/` | Node.js 18+ | VPS API: recebe catálogo, serve o app |
| `mobile/` | Flutter 3.x | App do vendedor (offline-first) |

---

## Passo 1 — Configurar o Worker .NET

### `worker/appsettings.json`

```json
{
  "Firebird": {
      "Host":     "192.168.1.100",
      "Port":     3050,
      "Database": "C:\\ERP\\PIVETA.FDB",
      "User":     "SYSDBA",
      "Password": "sua_senha_aqui",
      "Charset":  "WIN1252",
      "Dialect":  3,
      "WireCrypt": true
    },
  "VpsApi": {
    "BaseUrl": "https://seu-servidor.com",
    "ApiKey":  "sua-api-key-aqui"
  },
  "Worker": {
    "CatalogSyncIntervalMinutes":    15,
    "OrderSyncIntervalMinutes":       2,
    "HealthCheckIntervalMinutes":     5
  }
}
```

> **Nunca commite `appsettings.json` com senhas reais.** Use `appsettings.Production.json` (ignorado pelo `.gitignore`).

### Instalar como Windows Service

```powershell
# Executar como Administrador, na pasta worker/
.\install_service.ps1 -ForceBuild

# Monitorar logs em tempo real
Get-Content logs\worker-*.log -Tail 50 -Wait
```

**Comportamento do circuit-breaker:** Se o Firebird ficar offline ≥3 verificações de health check consecutivas, o sync de catálogo é automaticamente suspenso. Ele retoma assim que o banco se recuperar.

---

## Passo 2 — Configurar o Middleware VPS (Node.js)

### `middleware/.env`

```env
# ── Firebird — lido pelo middleware para health check e pedidos ────────────
FB_MOCK=false

FB_HOST=192.168.1.100
FB_PORT=3050
FB_DATABASE=/caminho/para/COLISEU.FDB
FB_USER=SYSDBA
FB_PASSWORD=sua_senha_aqui

FB_POOL_MIN=3
FB_POOL_MAX=15
# Criptografia de wire (Firebird WireCrypt). Manter true em produção.
FB_WIRE_CRYPT=true

# ── Middleware ──────────────────────────────────────────────────────────────
PORT=3000
API_KEY=coliseu-sales-prod-key-aqui   # Mesma chave em VpsApi:ApiKey do Worker!
NODE_ENV=production
```

### Iniciar o Middleware

```bash
cd middleware/
npm install
npm start           # Produção
# ou
npm run dev         # Desenvolvimento com reload automático
```

---

## Passo 3 — Executar o Script DDL no Firebird

Execute via FlameRobin → *Execute SQL Script* ou `isql`:

```
middleware/sql/001_create_base_tables.sql
```

Isso cria as tabelas `SALES_ORDERS`, `SALES_ORDER_ITEMS` e `SYNC_LOG`.

Em seguida, execute também o DDL 002:

```
middleware/sql/002_sync_orders_control.sql
```

Isso cria a tabela `SYNC_ORDERS` (controle de idempotência de pedidos), índices de performance e a stored procedure `SP_PURGE_OLD_SYNC_ORDERS` (limpeza automática de registros antigos).

> **Verificar:** As tabelas devem aparecer no painel "Tables" do FlameRobin.

---

## Passo 4 — Validar o Sistema

### 4.1 Health check do Middleware

```powershell
# Deve retornar { status: "ok", firebird: "connected" }
Invoke-RestMethod http://localhost:3000/health
```

Se retornar `"firebird": "mock"`, o `FB_MOCK` ainda está `true` no `.env`.

### 4.2 Verificar logs do Worker

```powershell
# Confirmar que o Worker conectou e sincronizou
Get-Content worker\publish\logs\worker-*.log -Tail 30
```

Procure por:
- `[HealthCheck] ✓ Firebird: OK | VPS API: OK`
- `[CatalogSync/Catalog] X produtos sincronizados`
- `[CatalogSync/Sellers] X vendedores enviados`

### 4.3 Primeira sincronização no App

1. Abra o app → verifique barra verde **"Online"**
2. `AutoSyncService` dispara automaticamente em ≤15min
3. Ou, na **tela de Sincronização**, tap em **"Sincronizar Agora"**
4. Verifique no FlameRobin se os pedidos preencheram `SALES_ORDERS`

---

## Troubleshooting

| Sintoma | Causa provável | Solução |
|---|---|---|
| `[HealthCheck] ✗ Firebird INDISPONÍVEL` | IP/porta errado ou banco offline | Verificar `Firebird:Host` e `Firebird:Port` no `appsettings.json` |
| `DB_NOT_FOUND` | Caminho do `.FDB` errado | Usar caminho absoluto completo no servidor, sem alias |
| `LOGIN_FAILED` | Usuário/senha errados | Testar login no FlameRobin com as mesmas credenciais |
| Circuit-breaker aberto | 3+ falhas consecutivas no Firebird | Verificar conectividade; o circuit fecha automaticamente após 5min ou quando o banco voltar |
| Catálogo não chega no app | VPS API offline ou vps ApiKey errada | Checar `VpsApi:BaseUrl` e `VpsApi:ApiKey` no Worker; testar `/health` na VPS |
| `firebird: "mock"` no health da VPS | `FB_MOCK=true` no `.env` | Alterar para `FB_MOCK=false` e reiniciar o middleware |
| Produtos não aparecem no app | Sync pendente ou tabela com nome diferente | Verificar logs do Worker; colunas mapeadas em `SyncCatalogJob.cs` |
| Espécies/Naturezas não aparecem | Chave de resposta da API errada | `pullPaymentSpecies` espera `paymentMethods`, `pullNatureza` espera `natureza` — verificar versão do middleware |
| Pedidos com erro não registram em `SYNC_ORDERS` | DDL 002 não executado | Executar `002_sync_orders_control.sql` no Firebird |

---

## Comandos de Administração do Worker

```powershell
Get-Service ColiseuSalesWorker | Format-List   # Status detalhado
Stop-Service ColiseuSalesWorker                # Parar
Start-Service ColiseuSalesWorker               # Iniciar
Restart-Service ColiseuSalesWorker             # Reiniciar
.\install_service.ps1 -Remove                  # Desinstalar
.\install_service.ps1 -ForceBuild              # Reinstalar com rebuild
```
