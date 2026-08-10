# SPEC-worker-erp

## Responsabilidades
O Worker .NET invisível roda na mesma rede física do banco Firebird do Auto Center. O aplicativo nunca atinge o Firebird por fora; o Worker atua como firewall e motor de integração confiável.
A interface visual de controle deste Worker é administrada pelo **Configurator Global WinForms**, responsável por definir credenciais, links base e módulos ligados em um `appsettings.json` unificado.

## Regras de Sincronização
- **Sincronismo de Orçamentos (Push-Pull):** O Worker filtra apenas as intenções `STATUS=APPROVED` listadas pelo Middleware de volta para o ambiente. Uma vez cadastrado no banco nativo de Firebird do pátio, a label muda de Orçamento a "Gerado/Efetivado" final atrelando um "ID do ERP" original.
- **Sincronismo de Clientes (Unidirecional Push):** `SyncAutoCenterCustomersJob` lê todos os cadastros ativos na base principal (Firebird) em lotes (threshold normalizado 500 itens). O Worker remete (`POST /internal/customers/sync`) de maneira autoritativa o ecossistema ativo de clientes para uso "Offline-first" pelo App local.
- **Filtro de Relevância e Dependência:** Componentes AutoCenter são injetados de maneira condicionada sob `AutoCenterApiOptions.Enabled`.
- **Graceful Shutdown:** Antes de o processo cair no Windows Server pra update da Service, o código fará "Graceful Shutdown": recusa leitura nova de queues e emite `Rollback` nas conexões soltas do Firebird locais transacionáveis (`ExecuteInTransactionAsync<T>`).
- **Health Checks:** Monitoramento do Worker deve injetar pulso contínuo informando à VPS que a oficina está online. No de painel caindo, a fila VPS engorda até retorno do Worker.
