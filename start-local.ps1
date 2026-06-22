# start-local.ps1
param($FirebirdDb = "C:\Coliseu\Data\PIVETA.FDB", $FirebirdPass = "masterkey")

$Root = $PSScriptRoot
$ApiDir = Join-Path $Root "api"
$WrkDir = Join-Path $Root "worker"
$IdentityDir = Join-Path $Root "Coliseu.Identity\src\Coliseu.Identity.Api"

# Update config
$wrkSettings = Join-Path $WrkDir "appsettings.Development.json"
$cfg = Get-Content $wrkSettings | ConvertFrom-Json
$cfg.Firebird.Database = $FirebirdDb
$cfg.Firebird.Password = $FirebirdPass
$cfg | ConvertTo-Json -Depth 5 | Set-Content $wrkSettings

# Start Identity
Start-Process powershell -ArgumentList '-NoExit', '-Command', "cd '$IdentityDir'; dotnet run --environment Development"
Start-Sleep 5

# Start API
Start-Process powershell -ArgumentList '-NoExit', '-Command', "cd '$ApiDir'; dotnet run --environment Development"
Start-Sleep 5

# Start Worker
Start-Process powershell -ArgumentList '-NoExit', '-Command', "cd '$WrkDir'; dotnet run --environment Development"

Write-Host '=== Backend iniciado! ==='
