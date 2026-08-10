using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using System.Threading.Tasks;
using ColiseuSales.Worker.Config;
using ColiseuSales.Worker.Services;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace ColiseuSales.Worker.Jobs
{
    public record AutoCenterSellerDto(
        [property: JsonPropertyName("id")] string Id,
        [property: JsonPropertyName("mobileId")] string MobileId,
        [property: JsonPropertyName("name")] string Name,
        [property: JsonPropertyName("email")] string Email,
        [property: JsonPropertyName("passwordHash")] string PasswordHash,
        [property: JsonPropertyName("maxDiscount")] decimal? MaxDiscount,
        [property: JsonPropertyName("commissionRate")] decimal? CommissionRate,
        [property: JsonPropertyName("active")] bool Active
    );

    public sealed class SyncAutoCenterSellersJob
    {
        private readonly FirebirdService _firebird;
        private readonly IHttpClientFactory _httpClientFactory;
        private readonly ILogger<SyncAutoCenterSellersJob> _logger;
        private readonly StatusStore _status;
        private readonly SemaphoreSlim _lock = new(1, 1);

        public SyncAutoCenterSellersJob(
            FirebirdService firebird,
            IHttpClientFactory httpClientFactory,
            ILogger<SyncAutoCenterSellersJob> logger,
            StatusStore status)
        {
            _firebird = firebird;
            _httpClientFactory = httpClientFactory;
            _logger = logger;
            _status = status;
        }

        public async Task RunAsync(CancellationToken ct = default)
        {
            if (!await _lock.WaitAsync(0, ct))
            {
                return;
            }

            try
            {
                _logger.LogInformation("[AutoCenterSellerSync] Buscando vendedores no Firebird...");
                var rows = await _firebird.QueryAsync(@"
                    SELECT
                        F.ID_FUNCIONARIO  AS id,
                        F.ID_MOBILE       AS mobileId,
                        F.NOME            AS name,
                        F.EMAIL           AS email,
                        F.MOB_SENHA       AS passwordHash,
                        F.DESCONTO_MAX    AS maxDiscount,
                        F.COMISSAO        AS commissionRate
                    FROM FUNCIONARIOS F
                    WHERE F.MOB_ACESSO = 1
                    ORDER BY F.NOME", ct: ct);

                if (rows.Count == 0)
                {
                    _logger.LogWarning("[AutoCenterSellerSync] Nenhum vendedor com MOB_ACESSO=1 encontrado.");
                    return;
                }

                var sellers = new List<AutoCenterSellerDto>();
                foreach (var r in rows)
                {
                    try
                    {
                        var id = r.GetValueOrDefault("id")?.ToString() ?? "";
                        if (string.IsNullOrEmpty(id) || id == "0") continue;

                        var name = r.GetValueOrDefault("name")?.ToString() ?? "";
                        var mobileId = r.GetValueOrDefault("mobileId")?.ToString() ?? "";
                        var email = r.GetValueOrDefault("email")?.ToString() ?? "";
                        var passwordHash = r.GetValueOrDefault("passwordHash")?.ToString() ?? ""; // MOB_SENHA

                        decimal? maxDiscount = null;
                        if (decimal.TryParse(r.GetValueOrDefault("maxDiscount")?.ToString(), out var md))
                        {
                            maxDiscount = md;
                        }

                        decimal? commissionRate = null;
                        if (decimal.TryParse(r.GetValueOrDefault("commissionRate")?.ToString(), out var cr))
                        {
                            commissionRate = cr;
                        }

                        sellers.Add(new AutoCenterSellerDto(
                            id,
                            mobileId,
                            name,
                            email,
                            passwordHash,
                            maxDiscount,
                            commissionRate,
                            true // active by default
                        ));
                    }
                    catch (Exception ex)
                    {
                        _logger.LogWarning("[AutoCenterSellerSync] Erro ao mapear linha de vendedor: {Err}", ex.Message);
                    }
                }

                if (sellers.Count == 0) return;

                _logger.LogInformation("[AutoCenterSellerSync] Enviando {Count} vendedores para o AutoCenter Middleware...", sellers.Count);
                
                var client = _httpClientFactory.CreateClient("AutoCenterApiClient");
                
                // Realiza POST para /internal/sellers/sync
                var res = await client.PostAsJsonAsync("/internal/sellers/sync", sellers, ct);

                if (res.IsSuccessStatusCode)
                {
                    _logger.LogInformation("[AutoCenterSellerSync] Sincronização concluída com sucesso. {Count} vendedores enviados.", sellers.Count);
                    _status.AppendLog($"[{DateTime.Now:HH:mm:ss}] ✓ [AutoCenter] Vendedores Sincronizados: {sellers.Count}");
                }
                else
                {
                    var body = await res.Content.ReadAsStringAsync(ct);
                    _logger.LogError("[AutoCenterSellerSync] Falha ao enviar vendedores para o middleware: {Status} | {Body}", res.StatusCode, body);
                }
            }
            catch (Exception ex)
            {
                _logger.LogError("[AutoCenterSellerSync] Erro crítico no Sync de Vendedores: {Err}", ex.Message);
            }
            finally
            {
                _lock.Release();
            }
        }
    }
}
