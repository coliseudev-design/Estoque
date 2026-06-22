# SPEC 02: Identity Server (.NET) Backend

## 1. Visão Geral
Esta documentação cobre as mudanças na camada da Identity API (C# .NET 8) do Coliseu Sales para dar suporte à autenticação, cadastro e controle de filiais (Branches). Sendo o guardião central de acesso do sistema (o *SSOT* das licenças), é aqui onde o login inicial do usuário acontece e autorizações são emitidas via JWT tokens.

## 2. Entidade de Domínio

### 2.1 Branch.cs
Deve ser criada em `Coliseu.Identity.Domain.Entities` seguindo as diretrizes do nosso `Clean Architecture` (Rule 06).
Semelhante à classe `Company.cs`, a classe `Branch.cs` deve conter propriedades espelhando o banco de dados e métodos de factory/autovalidação:
*   `Create(...)`
*   `UpdateDetails(...)`
*   Status change (Ativar, Desativar)

## 3. Endpoints Admin API (Gestão de Multi-Empresa)

Em `Coliseu.Identity.API/Controllers/Admin` (ou `Endpoints`), a gestão administrativa requer atestar `IsAdmin=true`:

*   `GET /admin/companies/{id}/branches`: Retorna a lista completa de branches de uma Company específica.
*   `POST /admin/companies/{id}/branches`: Insere um novo Branch.
*   `PUT /admin/companies/{id}/branches/{branchId}`: Atualiza os dados do Branch.
*   `DELETE /admin/companies/{id}/branches/{branchId}`: Desativa o branch (soft-disable recomentado para não perder logs).

## 4. Endpoints Device API (O App)

Os vendedores logam via App Mobile utilizando DeviceUUID e PIN, e no novo modelo, cruzarão permissões de filiais para selecionar onde irão trabalhar na sessão atual.

### 4.1 Novo FLUXO / Rota de Seleção: `POST /auth/select-branch`
O vendedor que logar passará primeiro pela tela de Login normal (que o valida num JWT Device padrão). Com isso ele adquire permissão (como uma porta de entrada do "Lobby").

O Device fará uma API call requisitando "selecionar" a filial 2 (Branch ID tal). O backend irá:
1. Validar se o Device JWT é existente e qual é a `CompanyId`.
2. Validar se aquele `branchId` pertence àquela `CompanyId`.
3. Validar se o usuário logado possui esse acesso nas permissões do ERP.
4. **Gerar um NOVO JWT**: Emitir um token substituto carregando os "claims" específicos dessa filial:
   *   `branchId`: (UUID do banco Identity)
   *   `erpEmpresaId`: (O ID_EMPRESA lá do Firebird)
   *   `deptoPadrao`: (O DEPTO_PADRAO da filial)
   *   `centroPadrao`: (O CENTRO_CUSTO da filial)

## 5. Próximos Passos (Checklist do Agente)
1. Criar `Branch.cs`.
2. Modificar o construtor e relações via Fluent API (`IdentityDbContext.cs`).
3. Adicionar lógica de verificação de permissões do Vendedor no `JwtService`.
