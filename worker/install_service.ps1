# install_service.ps1 — v2
# Instala o Coliseu Sales Worker como Windows Service.
#
# Fluxo:
#   1. Verifica execução como Administrador
#   2. Publica o binário (.NET 8 self-contained) se não existir ou se -ForceBuild
#   3. Remove serviço antigo (se houver)
#   4. Cria e configura o serviço Windows
#   5. Configura recovery automático (3 restarts com backoff)
#   6. Inicia o serviço e confirma status
#
# Uso:
#   .\install_service.ps1                          # Instalar (build se necessário)
#   .\install_service.ps1 -ForceBuild              # Recompilar antes de instalar
#   .\install_service.ps1 -Remove                  # Apenas remover o serviço
#
# Executar como Administrador (obrigatório).

#Requires -Version 5.1

param(
    [string]$ServiceName = "ColiseuSalesWorker",
    [string]$DisplayName = "Coliseu Sales - Worker Service",
    [string]$Description = "Sincroniza dados entre o ERP Firebird e a VPS Coliseu Sales",
    [string]$ProjectPath = "$PSScriptRoot",
    [string]$PublishDir = "$PSScriptRoot\publish",
    [string]$ExePath = "$PSScriptRoot\publish\ColiseuSales.Worker.exe",
    [switch]$ForceBuild = $false,
    [switch]$Remove = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─────────────────────────────────────────────────────────────────────────────
# Funções auxiliares
# ─────────────────────────────────────────────────────────────────────────────

function Write-Step([string]$msg) {
    Write-Host "`n>>> $msg" -ForegroundColor Cyan
}

function Write-Ok([string]$msg) {
    Write-Host "  [OK] $msg" -ForegroundColor Green
}

function Write-Warn([string]$msg) {
    Write-Host "  [AVISO] $msg" -ForegroundColor Yellow
}

function Write-Fail([string]$msg) {
    Write-Host "  [ERRO] $msg" -ForegroundColor Red
}

# ─────────────────────────────────────────────────────────────────────────────
# 1. Verificar privilégios de Administrador
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Verificando privilegios de Administrador"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $isAdmin) {
    Write-Fail "Este script precisa ser executado como Administrador."
    Write-Host "  Clique com o botao direito no PowerShell e selecione 'Executar como administrador'."
    exit 1
}
Write-Ok "Executando como Administrador."

# ─────────────────────────────────────────────────────────────────────────────
# 2. Modo de remoção
# ─────────────────────────────────────────────────────────────────────────────

if ($Remove) {
    Write-Step "Removendo servico: $ServiceName"
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($svc) {
        Stop-Service  -Name $ServiceName -Force -ErrorAction SilentlyContinue
        sc.exe delete $ServiceName | Out-Null
        Write-Ok "Servico removido com sucesso."
    }
    else {
        Write-Warn "Servico '$ServiceName' nao encontrado."
    }
    exit 0
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. Publicar o binário (se necessário)
# ─────────────────────────────────────────────────────────────────────────────

$needsBuild = $ForceBuild -or (-not (Test-Path $ExePath))

if ($needsBuild) {
    Write-Step "Publicando binario .NET 8 (self-contained, win-x64)..."

    # Verificar se dotnet está disponível
    $dotnetVersion = dotnet --version 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Fail ".NET SDK nao encontrado. Instale em https://dotnet.microsoft.com/download"
        exit 1
    }
    Write-Ok ".NET SDK: $dotnetVersion"

    # Publicar
    $csprojFiles = Get-ChildItem -Path $ProjectPath -Filter "*.csproj" -Recurse | Select-Object -First 1
    if (-not $csprojFiles) {
        Write-Fail "Nao foi possivel encontrar arquivo .csproj em: $ProjectPath"
        exit 1
    }

    Write-Host "  Projeto: $($csprojFiles.FullName)"
    dotnet publish $csprojFiles.FullName `
        --configuration Release `
        --runtime win-x64 `
        --self-contained true `
        --output $PublishDir `
        -p:PublishSingleFile=true `
        -p:IncludeNativeLibrariesForSelfExtract=true

    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Falha ao publicar. Verifique os erros acima."
        exit 1
    }
    Write-Ok "Publicado em: $PublishDir"
}
else {
    Write-Step "Binario ja existe. Use -ForceBuild para recompilar."
    Write-Ok "Usando: $ExePath"
}

# Verificação final do executável
if (-not (Test-Path $ExePath)) {
    Write-Fail "Executavel nao encontrado em: $ExePath"
    Write-Fail "Verifique o nome do projeto e tente novamente com -ForceBuild."
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. Remover serviço existente (se houver)
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Verificando servico existente: $ServiceName"
$existing = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Warn "Servico existente encontrado. Removendo..."
    Stop-Service  -Name $ServiceName -Force -ErrorAction SilentlyContinue
    sc.exe delete $ServiceName | Out-Null
    Start-Sleep 2
    Write-Ok "Servico anterior removido."
}
else {
    Write-Ok "Nenhum servico anterior encontrado."
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. Criar o serviço Windows
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Criando servico: $ServiceName"

sc.exe create $ServiceName `
    binPath= "`"$ExePath`"" `
    DisplayName= "$DisplayName" `
    start= auto

if ($LASTEXITCODE -ne 0) {
    Write-Fail "Erro ao criar o servico (exit code: $LASTEXITCODE)"
    exit 1
}
Write-Ok "Servico criado."

# Descrição
sc.exe description $ServiceName "$Description" | Out-Null

# ─────────────────────────────────────────────────────────────────────────────
# 6. Configurar recovery automático (3 tentativas com backoff)
#    Reset do contador: a cada 24h
#    Restart 1: após 5s, Restart 2: após 30s, Restart 3: após 60s
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Configurando recovery automatico"
sc.exe failure $ServiceName reset= 86400 actions= restart/5000/restart/30000/restart/60000 | Out-Null
Write-Ok "Recovery configurado: restart em 5s → 30s → 60s (reset em 24h)."

# ─────────────────────────────────────────────────────────────────────────────
# 7. Iniciar o serviço
# ─────────────────────────────────────────────────────────────────────────────

Write-Step "Iniciando servico..."
try {
    Start-Service -Name $ServiceName
    Start-Sleep 3
    $status = Get-Service -Name $ServiceName
    $color = if ($status.Status -eq "Running") { "Green" } else { "Red" }
    Write-Host "  Status: $($status.Status)" -ForegroundColor $color

    if ($status.Status -ne "Running") {
        Write-Fail "Servico nao iniciou corretamente. Verifique os logs do Windows Event Viewer."
        exit 1
    }
}
catch {
    Write-Fail "Erro ao iniciar servico: $_"
    Write-Host "  Verifique os logs em: $PublishDir\logs\"
    exit 1
}

# ─────────────────────────────────────────────────────────────────────────────
# Conclusão
# ─────────────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "=========================================" -ForegroundColor Green
Write-Host "  Coliseu Sales Worker instalado!        " -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Comandos uteis:" -ForegroundColor Cyan
Write-Host "  Logs:       Get-Content '$PublishDir\logs\worker-*.log' -Tail 50 -Wait"
Write-Host "  Parar:      Stop-Service $ServiceName"
Write-Host "  Iniciar:    Start-Service $ServiceName"
Write-Host "  Reiniciar:  Restart-Service $ServiceName"
Write-Host "  Status:     Get-Service $ServiceName | Format-List"
Write-Host "  Remover:    .\install_service.ps1 -Remove"
Write-Host "  Recompilar: .\install_service.ps1 -ForceBuild"
Write-Host ""
