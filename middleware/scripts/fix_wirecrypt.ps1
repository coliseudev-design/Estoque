$svc = "FirebirdServerDefaultInstance"
Write-Host "Parando Firebird..."
Stop-Service -Name $svc -Force
Start-Sleep -Seconds 3
Write-Host "Iniciando Firebird..."
Start-Service -Name $svc
Start-Sleep -Seconds 3
$status = (Get-Service -Name $svc).Status
Write-Host "Status: $status"
