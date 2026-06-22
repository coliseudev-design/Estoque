# Guia de Homologação e Publicação iOS (App Store Connect)

Este guia orienta passo a passo o processo de preenchimento dos metadados da loja, geração automática de ícones e upload automatizado do build (.ipa) para o TestFlight e App Store utilizando o Fastlane.

---

## 🛡️ Relatório de Auditoria Apple App Review & DevOps

Como parte da revisão de conformidade com as diretrizes da Apple (App Store Review Guidelines) e práticas recomendadas de DevOps, as seguintes correções críticas foram aplicadas no seu projeto:

1.  **Ignorar Conformidade de Criptografia Externa (ITSAppUsesNonExemptEncryption):**
    *   *Risco de Rejeição/Atraso:* Por padrão, ao subir novos builds para o TestFlight, o App Store Connect bloqueia a liberação para testes exibindo o status "Conformidade ausente" (Missing Compliance), exigindo que você responda manualmente se o app usa criptografia.
    *   *Solução Aplicada:* Adicionei a chave `<key>ITSAppUsesNonExemptEncryption</key><false/>` diretamente no seu arquivo [Info.plist](file:///Users/kleber/Documents/GitHub/ColiseuSales/mobile/ios/Runner/Info.plist). Isso informa a Apple que o app utiliza apenas conexões HTTPS padrão, liberando o TestFlight **instantaneamente** após o processamento da Apple.
2.  **Estruturação de Metadados por Idioma (pt-BR):**
    *   *Erro de Automação:* O Fastlane Deliver exige que os arquivos de metadados fiquem em pastas com os códigos de idioma (ex: `pt-BR`). Se deixados na raiz da pasta de metadados, o Fastlane não os envia.
    *   *Solução Aplicada:* Estruturei a pasta de metadados dentro de `metadata/pt-BR/` e configurei os arquivos `Fastfile` com o parâmetro `metadata_path` apontando diretamente para esta pasta.
3.  **Configuração de Bundle ID:**
    *   *Solução Aplicada:* O arquivo `Appfile` do Fastlane foi configurado de forma nativa com o Bundle ID correto do seu app: `com.kleber.coliseusalesdev`.

---

## 📂 Estrutura de Automação Criada

Na raiz do seu projeto foi criada a pasta `apple_store_submission/` com a seguinte organização:

*   `metadata/pt-BR/`: Contém os metadados reais pré-preenchidos do **Coliseu App** no formato exigido pelo Fastlane para upload automático.
*   `ios_config/`: Contém o template de permissões do `Info.plist` (`Info_privacy_snippets.plist`) e os arquivos de configuração do Fastlane (`Appfile` e `Fastfile`).
*   `assets_automation/`: Contém o script Python `generate_icons.py` responsável por cortar a imagem do ícone para todas as 21 resoluções exigidas pelo iOS.
*   `COMO_ENVIAR.md`: Este guia completo de instruções.

---

## 1. 📝 Preenchimento de Metadados (App Store Connect)

Os metadados foram pré-preenchidos na pasta `apple_store_submission/metadata/pt-BR/`. Quando você rodar o comando do Fastlane, ele subirá esses arquivos automaticamente. Se preferir colar manualmente pelo painel do [App Store Connect](https://appstoreconnect.apple.com):

1.  **`description.txt`** (Limite: 4.000 caracteres) -> *Versão do App > Descrição (Description)*.
2.  **`keywords.txt`** (Limite: 100 caracteres) -> *Versão do App > Palavras-chave (Keywords)*.
3.  **`privacy_url.txt`** (Obrigatório) -> *Informações do App > URL da Política de Privacidade*.
4.  **`marketing_url.txt`** (Opcional) -> *Informações do App > URL de Marketing*.
5.  **`support_url.txt`** (Obrigatório) -> *Versão do App > URL de Suporte*.
6.  **`whats_new.txt`** (Limite: 4.000 caracteres) -> *Versão do App > Novidades desta Versão*.
7.  **`promotional_text.txt`** (Limite: 170 caracteres) -> *Versão do App > Texto Promocional*.

---

## 2. 🎨 Geração Automatizada de Ícones (AppIcon)

O script `generate_icons.py` gera automaticamente todas as resoluções exigidas pela Apple para o catálogo de ícones `AppIcon.appiconset`.

### Passo a Passo:
1.  Caso queira trocar o ícone do aplicativo no futuro, cole a imagem em alta resolução (`1024x1024` pixels) na pasta `apple_store_submission/assets_automation/` com o nome **`icon.png`**.
2.  Abra o terminal na raiz do projeto e execute o script:
    ```bash
    python3 apple_store_submission/assets_automation/generate_icons.py
    ```
3.  O script irá detectar o projeto Flutter e perguntará se deseja copiar os ícones gerados.
    *   Digite `S` ou `Sim` (ou execute com a flag `--yes` para aceitar automaticamente no terminal/CI).
    *   Os ícones serão aplicados diretamente no Xcode em `mobile/ios/Runner/Assets.xcassets/AppIcon.appiconset/`.

---

## 3. 🛡️ Snippets de Privacidade (`Info.plist`)

A Apple exige justificativas claras para permissões.
*   O arquivo [Info.plist](file:///Users/kleber/Documents/GitHub/ColiseuSales/mobile/ios/Runner/Info.plist) do app **já possui a permissão de câmera configurada** para o scanner de código de barras.
*   Caso queira adicionar novas permissões no futuro (como geolocalização ou galeria de fotos), copie as chaves correspondentes do arquivo [Info_privacy_snippets.plist](file:///Users/kleber/Documents/GitHub/ColiseuSales/apple_store_submission/ios_config/Info_privacy_snippets.plist) e cole dentro do `<dict>` do seu `Info.plist`.

---

## 4. 🚀 Automação de Publicação com Fastlane

O Fastlane compila o arquivo `.ipa` e faz o upload para a Apple.

### 4.1 Preparação do Ambiente
Caso não possua o Fastlane instalado na sua máquina, instale via Homebrew:
```bash
brew install fastlane
```

### 4.2 Arquivos de Configuração no Projeto
Os arquivos de configuração já estão criados e integrados na pasta oficial do projeto em [mobile/ios/fastlane/](file:///Users/kleber/Documents/GitHub/ColiseuSales/mobile/ios/fastlane/).
*   **Ajuste Obrigatório no Appfile:** Abra o arquivo [Appfile](file:///Users/kleber/Documents/GitHub/ColiseuSales/mobile/ios/fastlane/Appfile) e preencha o seu e-mail da Apple em `apple_id` e o Team ID da Apple em `team_id`.

### 4.3 Executando os Comandos de Envio

#### A) Enviar para Homologação Interna (TestFlight)
Abra o terminal na pasta do iOS:
```bash
cd mobile/ios
fastlane beta
```
*O TestFlight será disponibilizado de forma instantânea para os seus testadores logo após o processamento devido ao bypass de criptografia configurado.*

#### B) Enviar para Publicação (App Store)
Abra o terminal na pasta do iOS:
```bash
cd mobile/ios
fastlane release
```
*Este comando compilará o app, lerá os metadados preenchidos de `apple_store_submission/metadata/pt-BR/` e enviará tudo de forma 100% automatizada para a App Store Connect.*

---

> [!TIP]
> **Evitando 2FA no Terminal / Integração Contínua (CI/CD):**
> Recomenda-se criar um **App Store Connect API Key** (chave `.p8`) no portal da Apple Developer (Usuários e Acesso > Integrações) e configurá-la no cabeçalho do seu `Fastfile`. Isso remove permanentemente a exigência de digitar senhas ou passar pela verificação em duas etapas no terminal.
