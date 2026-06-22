# Guia de Teste Local — Coliseu Sales

## Pré-requisitos

| Requisito | Verificar |
|---|---|
| **.NET 8 SDK** | `dotnet --version` → deve mostrar `8.x.x` |
| **Flutter SDK** | `flutter --version` |
| **Firebird 3.0** | Já rodando com o PIVETA.FDB |
| **Node.js (middleware)** | Opcional — pode ser parado após os testes com .NET |

**Instalar .NET 8 SDK:** https://dotnet.microsoft.com/download/dotnet/8.0

---

## Passo 1 — Configurar o caminho do banco Firebird

Edite `worker/appsettings.Development.json`:

```json
{
  "Firebird": {
    "Host": "localhost",
    "Port": 3050,
    "Database": "C:\\CAMINHO\\REAL\\PIVETA.FDB",  ← ajuste aqui
    "User": "SYSDBA",
    "Password": "sua_senha"
  }
}
```

---

## Passo 2 — Iniciar a API e o Worker

### Opção A — Script automático (recomendado)

```powershell
cd Coliseu_Sales

.\start-local.ps1 -FirebirdDb "C:\ERP\PIVETA.FDB" -FirebirdPass "sua_senha"
```

Isso abre **dois terminais**: um para a API e outro para o Worker.

### Opção B — Manual (dois terminais separados)

**Terminal 1 — API:**
```powershell
cd Coliseu_Sales\api
dotnet run --environment Development
```
✅ Aguarde: `Now listening on: http://localhost:5000`

**Terminal 2 — Worker:**
```powershell
cd Coliseu_Sales\worker
dotnet run --environment Development
```
✅ Aguarde: `[Worker] Coliseu Sales Worker iniciado.`

---

## Passo 3 — Verificar se está funcionando

### 3.1 Health check da API
```
http://localhost:5000/health
```
Resposta esperada:
```json
{ "status": "ok", "db": "ok", "time": "..." }
```

### 3.2 Documentação interativa (Scalar)
```
http://localhost:5000/scalar
```
Daqui você pode testar todos os endpoints manualmente.

### 3.3 Verificar logs do Worker
No terminal do Worker, após ~1 minuto você deve ver:
```
[CatalogSync] Iniciando sync. Mode=full
[CatalogSync/Sellers] N vendedores enviados. OK=True
[CatalogSync/Catalog] N produtos enviados. OK=True
[CatalogSync/Customers] N clientes enviados. OK=True
```

### 3.4 Verificar dados na API
```
http://localhost:5000/api/sync/sellers
```
Header obrigatório: `API-Key: dev-coliseu-sales-2026-secure-key-xyz`

---

## Passo 4 — Conectar o Flutter ao ambiente local

No arquivo `mobile/lib/service_locator.dart`, confirme:
```dart
const String _middlewareBaseUrl = 'http://10.0.2.2:5000'; // emulador Android
// ou 'http://localhost:5000' para iOS Simulator / web
```

> **⚠️ Emulador Android:** usa `10.0.2.2` para acessar o `localhost` do PC host

Rode o Flutter:
```powershell
cd Coliseu_Sales\mobile
flutter run
```

---

## Passo 5 — Teste end-to-end

| Passo | O que testar | Resultado esperado |
|---|---|---|
| 1 | Abrir o app Flutter | Tela de login carrega lista de vendedores |
| 2 | Selecionar ROBERSON | Tela de PIN aparece |
| 3 | Digitar PIN `4645` | Login bem-sucedido → tela principal |
| 4 | Navegar em Catálogo | Produtos carregados do SQLite local |
| 5 | Criar pedido e confirmar | Pedido aparece em `GET /api/orders/pending` |
| 6 | Aguardar ~1min | Worker processa e chama `MOB_CADASTRAR_PEDIDO` |
| 7 | Checar `GET /api/orders/{id}` | Status: `synced`, `erpOrderId` preenchido |

---

## Solução de problemas

| Erro | Causa | Solução |
|---|---|---|
| `Connection refused :5000` | API não está rodando | Rode `dotnet run` no diretório `api/` |
| `Firebird connection error` | Caminho do .FDB errado | Ajuste `Firebird.Database` no appsettings |
| `API Key inválida` | Header faltando | Usar `API-Key: dev-coliseu-sales-2026-secure-key-xyz` |
| `Vendedor não encontrado` | sellers table vazia | Aguardar 1min para Worker sincronizar |
| `flutter: Connection refused` | URL errada no Flutter | Usar `10.0.2.2:5000` para emulador Android |
| `Build failed: PendingOrderDto` | Conflito de DTOs (já corrigido) | Fazer `dotnet clean` e `dotnet build` |

---

## Estrutura de portas no ambiente local

```
Flutter (emulador)
    ↓ HTTP para 10.0.2.2:5000
ColiseuSales.Api  → localhost:5000 → coliseu_sales_dev.db (SQLite)
    ↑
ColiseuSales.Worker → localhost:5000 (push dados)
    ↓
Firebird PIVETA.FDB → localhost:3050
```
