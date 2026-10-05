# Coliseu Estoque — App

App Flutter de conferência cega para expedição. Funciona em celular comum (câmera)
e em coletores Zebra / Honeywell (leitor físico), online e offline.

## Primeira execução

As pastas de plataforma ainda não foram geradas. Gere uma vez e versione o resultado —
o `MainActivity.kt` já presente (ANDROID_ID para o vínculo de licença) é preservado:

```bash
cd app
flutter create . --org br.com.coliseusistemas --project-name coliseu_estoque --platforms=android,ios
flutter pub get
flutter run
```

iOS: adicione em `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>A câmera é usada para ler códigos de barras na conferência.</string>
```

## Fluxo

1. **Ativação do aparelho** — chave de ativação gerada no painel de licenças
   (módulo Estoque → Dispositivos). O app chama `/auth/device-login` do Identity com
   `moduleSlug: "estoque"`; a URL da API vem do módulo (campo URL do middleware).
2. **Login do operador** — usuário + PIN cadastrados no dashboard (Usuários).
   Funciona offline para o último operador que entrou online no aparelho.
3. **Fila** → escolhe o documento → **bipa** → **finaliza**.
   A API responde: concluído, recontar (lista de produtos) ou enviado ao supervisor.

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
