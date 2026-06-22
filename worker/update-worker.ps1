# update-worker.ps1
# Publica e reinstala o Coliseu Sales Worker com a nova versão (monitoramento SSE).
# IMPORTANTE: Execute como Administrador.

$WorkerSrc = "C:\Users\rober\OneDrive\Documentos\GitHub\ColiseuSales\worker"
$InstallDir = "C:\COLISEU SALES APLICACAO"
$ServiceName = "Coliseu Sales Worker"

Write-Host "===================================================" -ForegroundColor Cyan
Write-Host " Coliseu Sales Worker — Atualização" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan

# 1. Parar o serviço
Write-Host "`n[1/4] Parando o serviço '$ServiceName'..." -ForegroundColor Yellow
try {
    $svc = Get-Service -Name $ServiceName -ErrorAction Stop
    if ($svc.Status -ne "Stopped") {
        Stop-Service -Name $ServiceName -Force
        Start-Sleep -Seconds 3
        Write-Host "      Serviço parado." -ForegroundColor Green
    }
    else {
        Write-Host "      Serviço já estava parado." -ForegroundColor Gray
    }
}
catch {
    Write-Host "      Serviço não encontrado — continuando sem parar." -ForegroundColor Gray
}

# 2. Publicar o Worker
Write-Host "`n[2/4] Publicando Worker em modo Release..." -ForegroundColor Yellow
$pub = dotnet publish "$WorkerSrc\ColiseuSales.Worker.csproj" `
    -c Release -r win-x64 --self-contained `
    -o "$InstallDir\_publish_temp" 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERRO no publish:" -ForegroundColor Red
    Write-Host $pub
    exit 1
}
Write-Host "      Publicado com sucesso." -ForegroundColor Green

# 3. Copiar binários para a pasta de instalação
Write-Host "`n[3/4] Copiando binários para '$InstallDir'..." -ForegroundColor Yellow
Copy-Item "$InstallDir\_publish_temp\*" $InstallDir -Recurse -Force
Remove-Item "$InstallDir\_publish_temp" -Recurse -Force
Write-Host "      Copiado." -ForegroundColor Green

# 4. Iniciar o serviço
Write-Host "`n[4/4] Iniciando o serviço '$ServiceName'..." -ForegroundColor Yellow
try {
    Start-Service -Name $ServiceName
    Start-Sleep -Seconds 2
    $status = (Get-Service -Name $ServiceName).Status
    Write-Host "      Status: $status" -ForegroundColor Green
}
catch {
    Write-Host "      Não foi possível iniciar o serviço: $_" -ForegroundColor Red
    Write-Host "      Inicie manualmente em: Serviços do Windows > $ServiceName" -ForegroundColor Yellow
}

Write-Host "`n===================================================" -ForegroundColor Cyan
Write-Host " Atualização concluída!" -ForegroundColor Green
Write-Host " Monitore em: http://localhost:9001/status" -ForegroundColor Cyan
Write-Host " Abra o Configurador → aba Monitoramento" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan
