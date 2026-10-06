# Coliseu Estoque — App

App Flutter de conferência cega para expedição. Funciona em celular comum (câmera)
e em coletores Zebra / Honeywell (leitor físico), online e offline.

## Gerar o APK

```bash
cd app
flutter pub get
flutter build apk --release      # build/app/outputs/flutter-apk/app-release.apk
```

As pastas de plataforma Android já estão no repositório (`MainActivity.kt` expõe o
ANDROID_ID). O manifesto libera `http` (`usesCleartextTraffic`) para testar com a API na
rede local; em produção a API fica em `https`. Guia de teste: `../APP-TESTE/COMO-TESTAR.md`.

## Fluxo

1. **Conexão do aparelho** (uma vez):
   - **QR Code do painel** (padrão) — Painel → Cadastros → Aparelhos → Conectar aparelho.
     O QR traz `COLISEU-ESTOQUE|<endereço da API>|<código>`; o app troca o código
     (10 min, uso único) por uma credencial própria (`POST /v1/auth/pair`).
     Sem câmera: digita endereço + código. O supervisor desvincula na mesma tela.
   - **Chave de ativação** do painel de licenças (Coliseu.Identity) — `/auth/device-login`
     com `moduleSlug: "coliseu-estoque"`; a URL da API vem do módulo.
2. **Login do operador** — usuário + PIN cadastrados no dashboard (Usuários).
   Funciona offline para o último operador que entrou online no aparelho.
3. **Fila** separada em **Entradas** (notas de compra importadas pelo XML) e **Saídas**
   (pedidos do ERP), com as críticas de cada documento. Bipar o DANFE ou o nº do pedido
   na fila abre a conferência direto.
4. **Conferência** → bipa → **finaliza**. A API responde: concluído, recontar (lista de
   produtos) ou enviado ao supervisor.

## Offline

Toda leitura vai primeiro para o SQLite (`outbox`) com UUID próprio e só depois
para a API — reenviar nunca duplica. Sem internet o operador continua uma conferência
que já tinha iniciado no aparelho; a finalização exige conexão (é o servidor quem
compara com o documento, o app nunca recebe as quantidades esperadas).

## Coletores (keyboard wedge)

| Fabricante | Configuração |
|---|---|
| Zebra (DataWedge) | Perfil do app → Keystroke output **ligado**, *Send ENTER key* **ligado** |
| Honeywell | Data Processing → *Suffix* = Enter (`\r`) |
| Leitor Bluetooth/USB | modo HID teclado, sufixo Enter |

O app mantém um campo invisível com foco que recebe as teclas do leitor sem abrir o
teclado virtual (`lib/core/scan/scanner_input.dart`).

## Estrutura

```
lib/
  app/            tema e composição dos serviços
  core/
    api/          cliente HTTP (API do Estoque + Identity)
    config/       preferências (ativação, sessão, cursores do catálogo)
    db/           SQLite: outbox, catálogo, cache de documentos
    device/       identificador do aparelho
    scan/         entrada do leitor físico
    session/      ativação + login do operador (com PIN offline)
    sync/         descarga da fila e delta do catálogo
  features/       activation · login · documents · conference
  models/         contratos da API
```
