# Guia de Onboarding: Ativar Novo Módulo no Ecossistema Coliseu

## Visão Geral

Este guia documenta o processo completo para adicionar um novo cliente ao módulo **AutoCenter**,
ou ativar qualquer outro módulo do ecossistema Coliseu em uma empresa já cadastrada.

---

## Arquitetura do Ecossistema

```
┌─────────────────────────────────────────────────────────────────┐
│                    COLISEU IDENTITY SERVER                      │
│          (https://identity.coliseusistemas.com.br)              │
│                                                                 │
│   Tabela: companies  ──→  Tabela: company_modules               │
│      - id (UUID)              - id                              │
│      - name                   - company_id                      │
│      - status                 - module_slug  (autocenter /      │
│      - firebird config         coliseu-sales)                   │
│                               - api_key_hash                    │
│                               - device_limit                    │
│                               - middleware_base_url              │
│                               - is_active                       │
└─────────────────┬───────────────────────────┬───────────────────┘
                  │                           │
       ┌──────────▼───────────┐   ┌───────────▼──────────┐
       │   COLISEU SALES      │   │    AUTOCENTER        │
       │   Middleware (Node)  │   │   Middleware (Node)  │
       │   VPS: :3000         │   │   VPS: :3100         │
       └──────────┬───────────┘   └───────────┬──────────┘
                  │                           │
       ┌──────────▼───────────────────────────▼──────────┐
       │           WORKER (.NET) — Windows Service       │
       │     Roda na máquina do cliente (on-premise)     │
       │                                                 │
       │  Jobs AutoCenter (quando AutoCenterApi.Enabled  │
       │  = true no appsettings.json):                   │
       │    - SyncAutoCenterQuotesJob   (a cada 1min)   │
       │    - SyncAutoCenterCustomersJob (a cada 5min)  │
       │    - SyncAutoCenterCatalogJob  (a cada 5min)   │
       └─────────────────────────────────────────────────┘
```

---

## Passo 1: Cadastrar a Empresa (se ainda não existir)

1. Acesse o **Admin Panel**: `https://adminlicencas.coliseusistemas.com.br`
2. Navegue para **Empresas → Nova Empresa**
3. Preencha os dados da empresa
4. Salve — a empresa receberá um **UUID** (ex: `a1b2c3d4-...`)

---

## Passo 2: Adicionar o Módulo AutoCenter à Empresa

1. No Admin Panel, abra a empresa → seção **Módulos**
2. Clique em **"+ Adicionar Módulo"**
3. Preencha:
   - **Módulo**: `autocenter`
   - **Limite de Dispositivos**: ex: `5`
   - **URL do Middleware**: `https://autocenter.coliseusistemas.com.br`
4. Clique em **Salvar**
5. Uma **API Key** será gerada e exibida **UMA ÚNICA VEZ** → copie imediatamente

> [!CAUTION]
> A API Key nunca é exibida novamente. Se perder, utilize o botão **"Rotacionar Chave"** para gerar uma nova.

---

## Passo 3: Configurar o Worker na Máquina do Cliente

O Worker do Coliseu Sales (já instalado) precisa ser configurado para também sincronizar o AutoCenter.

**Arquivo**: `appsettings.json` na pasta de instalação do Worker

```json
{
  "AutoCenterApi": {
    "Enabled": true,
    "BaseUrl": "https://autocenter.coliseusistemas.com.br",
    "InternalApiKey": "COLE_AQUI_A_API_KEY_DO_MODULO",
    "TimeoutSeconds": 30
  },
  "IdentityApi": {
    "BaseUrl": "https://identity.coliseusistemas.com.br",
    "InternalApiKey": "CHAVE_INTERNA_DO_IDENTITY",
    "TenantId": "UUID_DA_EMPRESA_NO_IDENTITY"
  }
}
```

**Campos a preencher**:
- `AutoCenterApi.InternalApiKey` → API Key copiada no Passo 2
- `AutoCenterApi.Enabled` → `true`
- `IdentityApi.TenantId` → UUID da empresa (Painel → Empresas → copiar ID)

**Depois**: Reiniciar o Windows Service:
```powershell
Restart-Service "Coliseu Sales Worker"
```

---

## Passo 4: Ativar o Dispositivo no App AutoCenter

1. Instale o **AutoCenter App** no tablet/celular
2. Na primeira execução, a tela de ativação aparecerá automaticamente
3. Preencha:
   - **Servidor**: `https://identity.coliseusistemas.com.br`
   - **Chave de Ativação**: Gere uma chave no Admin Panel  
     _(Empresas → Dispositivos → Novo Dispositivo → Módulo: autocenter)_
4. Toque em **Ativar Dispositivo**

O app receberá automaticamente:
- JWT de autenticação
- URL do middleware AutoCenter (salva localmente no SecureStorage)
- Dados da empresa (nome, tenant ID)

---

## Passo 5: Verificar Funcionamento

### Worker (logs)
```
[AutoCenterSync] 🚗 1 orçamento(s) para integrar
[AutoCenterSync] Orçamento do AutoCenter inserido no Firebird. ERP ID: 1234
```

### Middleware (health check)
```
GET https://autocenter.coliseusistemas.com.br/health
→ { status: "ok", db: "ok", redis: "ok" }
```

### Identity Server (validação)
```
POST https://identity.coliseusistemas.com.br/internal/companies/{UUID}/modules/autocenter/validate-key
Headers: X-Internal-Api-Key: <chave_interna>
Body: { "apiKey": "<api_key_do_modulo>" }
→ { "valid": true }
```

---

## Criar um Novo Módulo (além do AutoCenter)

Para adicionar um módulo completamente novo ao ecossistema:

1. **Identity Server**: adicionar o slug em `ModuleSlugs.cs`:
   ```csharp
   public const string NovoModulo = "novo-modulo";
   ```

2. **Admin Panel**: o `ModulesSection.jsx` usa uma lista de slugs disponíveis — adicionar o novo slug no select do modal de criação

3. **Novo Middleware**: criar um serviço Node.js similar ao `autocenter/middleware`, usando o mesmo padrão de autenticação JWT + `EXPECTED_MODULE_SLUG=novo-modulo`

4. **Worker**: criar um `SyncNovoModuloJob.cs` usando o padrão de `SyncAutoCenterQuotesJob.cs` e adicionar ao `WorkerService.cs` com flag `Enabled`

5. **App Mobile**: seguir o padrão da `ActivationPage.dart`, trocando `moduleSlug: 'novo-modulo'`

---

## Troubleshooting

| Sintoma | Causa provável | Solução |
|---|---|---|
| App retorna "Módulo não habilitado" | Empresa sem módulo `autocenter` ativo | Admin Panel → adicionar módulo |
| Worker não sincroniza orçamentos | `AutoCenterApi.Enabled = false` | Editar `appsettings.json` e reiniciar service |
| "Chave inválida" no middleware | API Key incorreta ou rotacionada | Admin Panel → rotacionar chave → atualizar Worker |
| "Sessão expirada" no app | JWT expirado (24h) | Refazer ativação do dispositivo |
| "Limite de dispositivos atingido" | Empresa atingiu `DeviceLimit` do módulo | Admin Panel → aumentar limite |
| Worker mostra `⚠️ TenantId não configurado` | `IdentityApi.TenantId` está zerado | Copiar UUID da empresa do painel e configurar |

---

## URLs de Produção

| Serviço | URL |
|---|---|
| Identity Server (API) | `https://identity.coliseusistemas.com.br` |
| Admin Panel | `https://adminlicencas.coliseusistemas.com.br` |
| Coliseu Sales Middleware | `https://api.coliseusales.com.br` |
| AutoCenter Middleware | `https://autocenter.coliseusistemas.com.br` |

---

## Segurança

- **API Keys** são armazenadas como hashes SHA-256 — nunca em texto puro
- O middleware valida o claim `module: "autocenter"` no JWT — tokens do Sales não funcionam no AutoCenter e vice-versa
- O Worker usa `X-Internal-Key` (hash da API Key) para chamadas internas — nunca exposta publicamente
- Rotação de chave invalida imediatamente a chave antiga (cache de 5min no middleware)
