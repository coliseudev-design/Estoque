# Coliseu Speed — Documentação de Deploy

Sistema multi-tenant de integração ERP (Firebird) ↔ Mobile (Flutter) via middleware Node.js.

## Arquitetura

```
Flutter App ──── HTTP ────► Node.js Middleware ────► Firebird ERP
                               │         │
                            Redis     PostgreSQL
                           (cache)   (pedidos/empresas)
```

## ⚠️ Regras de Desenvolvimento (Views e Banco de Dados)

> **MANDATORY / OBRIGATÓRIO**: A partir de agora, **toda e qualquer nova View ou Procedure** que for criada para uso do Dash ou Mobile **DEVE** ser inserida no dicionário `RequiredViews` ou `RequiredProcedures` dentro de `ColiseuSpeed.Configurator/FirebirdBootstrapper.cs`.
> Nunca crie queries literais longas diretamente no código do Worker. Encapsule em Views no FirebirdBootstrapper e use queries simples no Worker (`SELECT * FROM VIEW`). O Configurator é a **única fonte de verdade** para preparar a estrutura de bancos de dados dos clientes.

## ⚠️ Regras de Compilação (Configurator & Worker)

**Aviso Crítico:** Todas as compilações do `Configurator` devem ser **obrigatóriamente** auto-contidas (Self-Contained) em um único arquivo (Single-File) e encapsulando o Worker. Isso garante que o instalador funcione em qualquer máquina Windows sem depender da instalação prévia do .NET Runtime 8.0. O tamanho final será em torno de 220MB+.

### Como Compilar Corretamente:
1. **Primeiro compile o Worker**:
   ```bash
   cd worker
   dotnet publish -c Release -r win-x64
   ```
2. **Depois compile o Configurator em Arquivo Único (com o Worker encapsulado)**:
   ```bash
   cd ../ColiseuSpeed.Configurator
   dotnet publish -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true
   ```

O executável final estará disponível em:
`ColiseuSpeed.Configurator/bin/Release/net8.0-windows/win-x64/publish/ColiseuSpeed.Configurator.exe`

## Início Rápido (Docker)

### Pré-requisitos
- Docker Desktop instalado
- `.env` configurado (veja `middleware/.env.example`)

```bash
# 1. Copiar configuração
cp middleware/.env.example middleware/.env
# Editar middleware/.env com suas senhas

# 2. Subir todos os serviços
docker-compose up -d

# 3. Verificar status
docker-compose ps
curl http://localhost:3000/health
```

## Onboarding de Nova Empresa

```bash
# Criar empresa e obter API Key
node middleware/scripts/onboard.js \
  --name "Empresa Coliseu XYZ" \
  --url http://localhost:3000 \
  --admin-key <ADMIN_API_KEY>

# A saída incluirá o trecho de appsettings.json para o Worker .NET
```

## Estrutura de Serviços

| Serviço | Porta | Descrição |
|---------|-------|-----------|
| Middleware | 3000 | API Node.js principal |
| PostgreSQL | 5432 | Dados persistentes (empresas, pedidos) |
| Redis | 6379 | Cache de catálogo por empresa (TTL 24h) |

## Rotas Principais

### Públicas
| Método | Rota | Descrição |
|--------|------|-----------|
| GET | `/health` | Status de todos os serviços |
| GET | `/metrics` | Métricas Prometheus |

### Admin (requer `Admin-Api-Key`)
| Método | Rota | Descrição |
|--------|------|-----------|
| GET/POST | `/api/admin/companies` | Listar / criar empresas |
| PATCH | `/api/admin/companies/:id` | Ativar / desativar |
| POST | `/api/admin/companies/:id/rotate-key` | Rotacionar API Key |
| GET/POST | `/api/admin/companies/:id/webhooks` | Gerenciar webhooks |

### Empresa (requer `API-Key` de empresa)
| Método | Rota | Descrição |
|--------|------|-----------|
| POST | `/api/sync/catalog` | Worker → push de produtos |
| POST | `/api/sync/customers` | Worker → push de clientes |
| POST | `/api/sync/cache/warm` | Re-popular cache após restart |
| GET | `/api/orders/pending` | Pedidos para o Worker processar |
| GET | `/api/orders/report` | Relatório paginado |
| GET | `/api/orders/kpi` | KPIs agregados |
| GET | `/api/orders/events` | Audit trail de pedidos |
| POST | `/api/orders/:id/confirm` | Worker confirma integração ERP |

## Testes de Isolamento

```bash
cd middleware
npm test -- --testPathPattern=isolation
```

## Variáveis de Ambiente

Ver `middleware/.env.example` para documentação completa.

## Migrations Automáticas

O middleware executa as migrations do PostgreSQL automaticamente no startup.
Arquivos em `middleware/sql/` são versionados via tabela `schema_migrations`.

## Componentes do Sistema

| Componente | Tecnologia | Função |
|-----------|-----------|--------|
| Middleware | Node.js 20 + Express | API central multi-tenant |
| Worker | .NET 8 | Sincroniza dados do Firebird |
| Mobile | Flutter 3 | App de vendas para vendedores |
| Admin | React + Vite | Painel de gestão |
| Banco | PostgreSQL 16 | Pedidos e empresas (RLS) |
| Cache | Redis 7 | Catálogo por empresa (TTL 24h) |
| ERP | Firebird | Banco de dados legado |
