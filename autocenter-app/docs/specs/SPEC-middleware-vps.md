# SPEC-middleware-vps

## Responsabilidades
Hospedar o estado central da sincronização entre as ferramentas da Nuvem e o pátio da oficina. É aqui que orçamentos viram verdade absoluta.
O componente mantém rotas nativas administrativas para uso irrestrito de injeção paralela pelos Workers locais de retaguarda (autenticação baseada em header customizado, `X-Internal-Key` e segmentada por `X-Tenant-Id`).

## Motor de Busca de Placas
A VPS recebe do ERP a placa a ser verificada (via Worker). Se o Flutter tentar consultar e tomar cache-miss:
1. Pinga a VPS no endpoint protegido.
2. A VPS executa `Fallback` consultando a `APIBrasil` ou fonte externa.
3. Se a API de Fallback falhar por estouro de cota (ex: `429 Too Many Requests`) ou erro originador `5xx`: Retornar payload avisando ao Flutter para destravar os campos e **habilitar a entrada manual de Marca/Modelo/Ano** no frontend.

## Proteções Operacionais
- **Autenticação Dupla:** As APIs estão protegidas por uma validação forte Híbrida: Client Apps assinam contra um modelo estrito em JWT validando um `expectedModuleSlug` evitando tokens cruzados, enquanto Microservices (como o Worker) transmitem injeções rápidas sob validação `requireInternalAuth`.
- **Particionamento Híbrido:** Operações pesadas como as consolidações diárias de Entidades de Clientes em Postgres lidam com `UUID` gerado baseado no Tenant a partir do `Coliseu.Identity`. Todos os `ON CONFLICT DO UPDATE` operam contra chaves duplas `(tenant_id, erp_id)`.
- **Validação Rigorosa:** Todos os Endpoints que disparam JSONs precisam validar RegEx de Placas (Mercosul/Antiga) e validar formato dos itens antes de aceitar.
- **Tratamento de Concorrência (409):** Mecânicos acessando a mesma placa na VPS tem que validar a flag de edição. Responder com `409 Conflict` apontando a string "O ticket já está em edição".
- **Liveness Probes:** Serviço contendo endpoints de `/health/liveness` providos pela arquitetura para rápida reinicialização.
