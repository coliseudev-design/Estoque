# Guia de Deploy em Produção — Coliseu Speed

Este guia descreve os passos para migrar do ambiente de teste local para a VPS de produção.

## 1. Banco de Dados (PostgreSQL)

O Middleware utiliza o PostgreSQL para filas e multi-tenancy.
- Os scripts de inicialização estão em `middleware/sql/`.
- **Atenção**: Os scripts em `middleware/sql/firebird/` são apenas para o banco local e não devem ser executados no Postgres da VPS.

## 2. Middleware Node.js (Linux VPS)

### Pré-requisitos
- Node.js 20+
- PM2 (`npm install -g pm2`)
- Nginx (Proxy Reverso)

### Passos
1. **Transferência:** Copie a pasta `middleware/` para a VPS.
2. **Configuração:** Crie o `.env` de produção baseado no `.env.example`.
   - `FB_WIRE_CRYPT=true` (obrigatório para conexões remotas).
   - `API_KEY`: Gere uma chave aleatória Forte (64+ chars).
3. **Execução:**
   ```bash
   npm install --production
   pm2 start src/index.js --name "coliseu-middleware"
   pm2 startup && pm2 save
   ```
4. **Proxy Reverso (Nginx):** Configure um domínio (ex: `api.suaempresa.com.br`) apontando para `localhost:3000` com SSL (Certbot).

---

## 2. Worker Service (.NET 8) (Windows Server Local)

### Pré-requisitos
- .NET 8 Runtime instalado no servidor onde está o Firebird.

### Passos
1. **Publicação:**
   ```powershell
   dotnet publish worker/ColiseuSpeed.Worker.csproj -c Release -o ./publish
   ```
2. **Instalação como Serviço Windows:**
   ```powershell
   # No Powershell como Admin
   New-Service -Name "ColiseuSpeedWorker" `
               -BinaryPathName "C:\Caminho\publish\ColiseuSpeed.Worker.exe" `
               -DisplayName "Coliseu Speed Worker" `
               -StartupType Automatic
   Start-Service "ColiseuSpeedWorker"
   ```
3. **Monitoramento:** Checar logs no Visualizador de Eventos (Event Viewer).

---

## 3. App Flutter (Distribuição)

O Google Play Console exige o formato **Android App Bundle (.aab)** para novos envios e atualizações. O formato APK clássico não é mais aceito para publicação direta na loja.

### Passo 1: Configurar a Assinatura do App (Keystore)
1. **Gerar a Keystore** (execute apenas uma vez se ainda não tiver uma chave):
   ```powershell
   keytool -genkey -v -keystore mobile/android/coliseu-release.jks `
     -alias coliseu -keyalg RSA -keysize 2048 -validity 36500 `
     -dname "CN=Coliseu Sistemas, OU=Mobile, O=Coliseu, L=BR, ST=BR, C=BR"
   ```
   *Guarde a senha e faça backup seguro do arquivo `.jks` gerado. Se você perdê-los, não conseguirá mais atualizar o app no Google Play.*

2. **Criar o Arquivo de Credenciais**:
   - Copie o arquivo `mobile/android/key.properties.example` para `mobile/android/key.properties`.
   - Edite o arquivo preenchendo as senhas e o caminho da chave (use barras normais `/` mesmo no Windows):
     ```properties
     storePassword=SUA_SENHA_AQUI
     keyPassword=SUA_SENHA_AQUI
     keyAlias=coliseu
     storeFile=../coliseu-release.jks
     ```
     *(O arquivo `key.properties` já está listado no `.gitignore` e não será enviado ao Git por motivos de segurança).*

### Passo 2: Configurar a API de Produção
- Certifique-se de que a URL de produção (HTTPS da VPS) está devidamente configurada em `mobile/lib/services/app_config_service.dart` ou correspondente.

### Passo 3: Compilar o Android App Bundle (.aab)
1. Abra o terminal na pasta `mobile`:
   ```bash
   cd mobile
   ```
2. Execute o comando de compilação:
   ```bash
   flutter build appbundle --release
   ```
3. O arquivo final assinado será gerado em:
   `mobile/build/app/outputs/bundle/release/app-release.aab`

*Nota: Se você ainda precisar de um APK para testes internos ou instalação direta (sideload), execute `flutter build apk --release`.*

---

## 4. Próximos Passos Sugeridos (Hardening)

1. **Sentry.io:** Integrar para capturar erros em tempo real:
   - App (Flutter)
   - Middleware (Node.js)
   - Worker (.NET)
2. **Backups:** Automatizar o backup do SQLite da VPS (`coliseu_speed.db`).
3. **Firewall:** Bloquear o porto 3000 externo da VPS, permitindo apenas acesso via Nginx (localhost).
