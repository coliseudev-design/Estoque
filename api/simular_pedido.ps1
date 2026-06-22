# simular_pedido.ps1
# Script para simular o envio de um pedido do App Flutter para a API .NET

$ApiUrl = "http://localhost:5000/api/sync/orders"
$ApiKey = "dev-coliseu-sales-2026-secure-key-xyz"

# Dados do Pedido
$OrderId = "TEST-" + (Get-Date -Format "yyyyMMdd-HHmmss")
$Body = @{
    orders = @(
        @{
            id               = $OrderId
            customerId       = "1"
            sellerId         = "105"
            totalAmount      = 150.50
            notes            = "Pedido de teste via script Antigravity"
            paymentSpeciesId = "1"
            paymentDays      = 30
            naturezaId       = "1"
            discountPercent  = 0
            discountValue    = 0
            items            = @(
                @{
                    productCode = "1013"
                    productName = "PRODUTO TESTE"
                    quantity    = 2
                    unitPrice   = 75.25
                    discount    = 0
                }
            )
        }
    )
} | ConvertTo-Json -Depth 10

Write-Host "Enviando pedido $OrderId para $ApiUrl..." -ForegroundColor Cyan

try {
    $Response = Invoke-RestMethod -Uri $ApiUrl -Method Post -Body $Body -ContentType "application/json" -Headers @{"API-Key" = $ApiKey }
    Write-Host "Resposta da API:" -ForegroundColor Green
    $Response | ConvertTo-Json
}
catch {
    Write-Host "Erro ao enviar pedido:" -ForegroundColor Red
    $_.Exception.Message
    if ($_.ErrorDetails) { $_.ErrorDetails.Message }
}
