# SPEC-architecture-core

## Objetivo
Definir o panorama do sistema e como as fronteiras se comunicam. O app não acessa diretamente o banco do sistema local, operando sob uma arquitetura de sincronismo assíncrono mediada pela Nuvem.

## Diagrama Funcional Híbrido

1. **Flutter App (Mobile):** Atua no dispositivo em campo. Foca no UI guiado e em empilhar requests offline mantendo um banco nativo em SQLite auto-sincronizável via REST (Client-Pull).
2. **PostgreSQL VPS (Middleware):** Banco ponte. Atende ao Flutter, consolida os Rascunhos/Orçamentos e valida os payloads. O backend funciona sob partições puras multitenant.
3. **.NET Worker (Rede Local do Auto Center):** Fica consumindo a VPS. Trabalha em fluxos combinados (Push-Pull): Escuta Orçamentos "Autorizados" para remeter localmente, e ejeta Master-Data massivo de "Clientes do ERP" de volta ao Middleware para os apps móveis.
4. **Configurator .NET WinForms (Admin/On-Premise):** Ferramenta UI visual para instalação nos servidores dos auto-centers definindo as strings de conexão cruzadas, tokens, URLs de endpoint na VPS e ativação/desativação de módulos operacionais como ERP e Placa.

## Tratamento de Erros Padronizado (API)

Toda recusa do Middleware e Resiliência do Worker gerará um output estruturado. O Client Flutter deve parsear:
```json
{
  "code": "VAL-001",
  "message": "Payload Tool Large",
  "details": "A requisição continha mais de 10 fotos anexadas, acima do threshold.",
  "timestamp": "2026-04-12T10:00:00.000Z"
}
```

## Status Universais Tratados

A entidade de Documento/Orçamento viaja entre os seguintes status:
- `DRAFT`: Local no Flutter (SQFlite).
- `ORCAMENTO`: Salvo com sucesso no Postgres da VPS. Compartilhado em Cloud.
- `CANCELADO`: O usuário decidiu ativamente desistir no pátio, finalizado no histórico da VPS (`Soft Delete`).
- `PEDIDO_GERADO`: Sucesso total. Worker .NET abraçou a venda e enviou pro Firebird.
