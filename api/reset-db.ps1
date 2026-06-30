# reset-db.ps1 — Reseta o banco SQLite da Sales API (apaga e recria com schema novo)
# ATENÇÃO: Este script apaga TODOS os dados do banco local.
# Use apenas em ambiente de desenvolvimento ou ao atualizar o schema.

param(
    [string]$DbPath = ".\coliseu_speed.db"
)

Write-Host "=== Coliseu Speed API — Reset de Banco de Dados ===" -ForegroundColor Cyan
Write-Host ""

# Confirmar antes de apagar em produção
$confirm = Read-Host "Isso vai APAGAR todos os dados de '$DbPath'. Confirma? (s/N)"
if ($confirm -ne 's' -and $confirm -ne 'S') {
    Write-Host "Operacao cancelada." -ForegroundColor Yellow
    exit
}

# Apagar o banco existente
if (Test-Path $DbPath) {
    Remove-Item $DbPath -Force
    Write-Host "✓ Banco '$DbPath' removido." -ForegroundColor Green
}
else {
    Write-Host "! Banco '$DbPath' nao encontrado — sera criado pelo startup da API." -ForegroundColor Yellow
}

# Apagar WAL e SHM se existirem
foreach ($ext in @("-wal", "-shm")) {
    $sidecar = "$DbPath$ext"
    if (Test-Path $sidecar) {
        Remove-Item $sidecar -Force
        Write-Host "✓ Arquivo sidecar '$sidecar' removido." -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Banco resetado. Execute 'dotnet run' na API para recriar o schema automaticamente." -ForegroundColor Cyan
Write-Host "O schema sera recriado com as colunas CompanyId e novos indices." -ForegroundColor Gray
