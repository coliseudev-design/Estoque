# SPEC-mobile-flutter

## Responsabilidades
O frontend nativo Flutter deve guiar o mecânico, manter o offline rodando bem e converter o Rascunho para Orçamento seguro.

## Regras de Interface e Conectividade
- **Skeleton Loading & Modo Offline:** Quando a rede cai, a transição entre telas não congela. Um `Toast` alerta a falha. O payload segue em fila SQLite via `workmanager`.
- **Botão Explícito de Cancelamento:** Na fase do pátio, permitir o encerramento da jornada com botão para "Cancelar Atendimento", empurrando `status=CANCELADO` via fila para a VPS.
- **Acesso Horizontal:** Não há trava de Gerente para envio à VPS. Qualquer mecânico no device consegue injetar o orçamente com sua sessão.

## Motor de Câmera e Restrições
- **Guia Visual:** Exibição de gabarito para não esquecer laterais, frente e traseira.
- **Limites de Midia:** Teto hard-coded de no máximo `8 a 10` fotos empacotadas por envio, para previnir tráfego e limite `413 Payload Too Large` na VPS.
- **Compressão:** Obrigatória redução cliente usando WebP/Jpeg (qualidade 80%) para prevenir `OutOfMemory` exceptions (OOM) no engine.

## Interceptores HTTP
- Timeout explícito de `15s` a `45s`.
- Retentativas via `Exponential Backoff` automático caso caia num `503 Service Unavailable`.
