# Deploy VPS — Novo Módulo e Middleware (AutoCenter)

Para concluir o deploy da nova arquitetura multi-app na VPS (Coolify), os seguintes passos são obrigatórios:

## 1. Subir a Nova Stack no Coolify
1. Acessar o Coolify -> Projects -> Coliseu Ecosystem.
2. Adicionar novo recurso via **Docker Compose**.
3. Colar o conteúdo de `docker-compose.autocenter.yml`.
4. Configurar as variáveis de ambiente em **Secrets**:
   - `JWT_DEVICE_KEY` = Mesma chave usada no Identity Server.
   - `PG_PASSWORD` = Senha do PostgreSQL.
   - `APIBRASIL_TOKEN` e `APIBRASIL_DEVICE_TOKEN` = Tokens para a consulta de placas.
   - `INTERNAL_API_KEY` = Chave de segurança interna usada para comunicações entre o Worker local das oficinas e este middleware.

### 1-A. Execução de Migrations de Banco
O middleware utiliza scripts de schema e migration de forma procedural. É obrigatório executar as migrações após o container subir:
```bash
# Conectar no container / shell do Postgres
psql -U coliseu_admin -d autocenter_db -f src/db/schema.sql
psql -U coliseu_admin -d autocenter_db -f src/db/migrations/002_customers.sql
psql -U coliseu_admin -d autocenter_db -f src/db/migrations/003_catalog.sql
```

## 2. Configuração de Rota (Nativo Node/Coolify)
**Importante:** Nós **removemos** as _labels_ manuais do Traefik de dentro do repositório para evitar conflito com o Coolify.
1. No painel do Coolify, acesse as "Configurações" do seu Recurso Docker Deployado.
2. Na aba de "Domains/Routing", adicione o Domínio: `https://autocenter.coliseusistemas.com.br` e referencie à Porta `3100`.
3. Certifique-se de que a aba "Healthcheck" está ligada na tela do Deploy. O Coolify reconhecerá nativamente a regra `http://localhost:3100/health/liveness` que embutimos na Fase 14.

## 3. Deploy do Identity Server (Importante)
A `Coliseu.Identity.Api` foi alterada para permitir requisições (CORS) a partir de `https://autocenter.coliseusistemas.com.br`.
1. Fazer **Redeploy** do recurso do Identity Server pelo Coolify.
2. Durante a inicialização do Identity Server, as dezenas de tabelas serão validadas e, como foram desenhadas de forma puramente idempotente, assegurarão a criação de tabelas novas (`company_modules`), colunas anexas (`ModuleSlug`), sem downtime.

## 4. Cadastro Administrativo
Com o deploy finalizado:
1. Abra o **Admin Panel** (`adminlicencas.coliseusistemas.com.br`).
2. Vá nos detalhes da Empresa, clique em "Adicionar Módulo" e selecione "AutoCenter".
3. Use a URL: `https://autocenter.coliseusistemas.com.br`.
4. Salve a Chave de Ativação revelada e pronto: Utilize no App AutoCenter para vinculação!

## 5. Instalação Local na Oficina (Worker v2.1.0+)
1. No Servidor ou Computador Principal da Oficina, execute `ColiseuSales_Configurator_v2.1.0.exe`.
2. Habilite as integrações, preenchendo as configurações do **AutoCenter** (URL HTTPS e a `INTERNAL_API_KEY` gerada no Passo 1).
3. O Configurator auto-popula o `appsettings.json` persistente de uso do _Worker de Sincronização_ local de background.
