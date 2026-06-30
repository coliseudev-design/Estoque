# SPEC 04: Frontend Mobile (Flutter) & Admin (React)

## 1. Visão Geral
Este documento cobre a interface do usuário (UI) e a experiência de usuário (UX) necessárias para gerir, selecionar e navegar entre o ambiente Multi-Filial do Coliseu Speed, exigindo alterações severas no fluxo de login e painel gerencial.

## 2. Painel Adminstrativo (React)

O controle total pelo escritório matriz e desenvolvedores.

### 2.1 UI de Configuração: `CompanyDetails.jsx`
*   No fluxo de edição das "Companies" (Clientes locatários do Coliseu), adicionar um controle em Abas (Tabs) para separar "Informações do Servidor" vs "Filiais (Branches)".
*   **Funcionalidade:** Tabela CRUD contendo filiais vinculadas, status (ativo/inativo), a Filial Default, bem como controle dos ponteiros `ID_EMPRESA`, `DEPTO_ESTOQUE`, `CENTRO_FINANCEIRO`. Esses numerais ditarão onde o App vai salvar/visualizar informações no ERP Firebird.

## 3. Aplicativo Mobile (Flutter)

No dispositivo do vendedor, uma mudança de estado crítica: a tela inicial agora divide o momento de Autenticação Central para a Navegação de Trabalho.

### 3.1 Tela `BranchSelectionScreen`
Após validar a contra-senha na `LoginScreen`, o vendedor avança e é bloqueado caso tenha >=2 filiais atreladas à sua permissão:
*   A tela exibe Botões Customizados/Cartões mostrando Nome Fantasia + CNPJ das Filiais que ele possui permissão no ERP.
*   Clicar envia API call local para `POST /auth/select-branch`.
*   O Mobile re-processa a sessão armazenando as chaves locais na classe de cache (via `AppConfigService`), configurando as strings temporárias de ID de navegação. Modos *Auto-Select* são ativados caso o vendedor limite-se a apenas 1 filial na relação do ERP (fazendo o skip sem mostrar a UI para não arrastar as vendas).

### 3.2 Interceptor Global Modificado
No módulo do Dio (`JwtInterceptor`), toda requisição sainte deverá ser incrementada com injeção automática de um Custom Header HTTP (exemplo: `X-Branch-Id: UUID`).
Isso obriga o Middleware Node a processar adequadamente o fetch Redis separado de estoque de cada unidade da empresa.

### 3.3 Labeling (Visual Hint) de Filial Atual
Visando UX em alto padrão: o app passará a evidenciar constantemente no cabeçalho ou menu lateral aberto qual é a `Branch` (Loja Centro, Logística Matriz) na qual ele está atuando atualmente, evitando confusão mental de venda lançada em caixa de faturamento cruzado. A cor temática e modo poderão sofrer sutil mudança se detectado perigo operacional.

### 3.4 Fluxo de Troca Lateral
Uma aba chamada "Alternar Filial" no Drawer deve possibilitar jogar o usuário de volta à tela `BranchSelectionScreen` resetando o cache em background que é pertinente somente ao branch.
