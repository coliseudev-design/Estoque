using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using System.Threading.Tasks;
using ColiseuSpeed.Worker.Config;
using ColiseuSpeed.Worker.Services;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace ColiseuSpeed.Worker.Jobs
{
    public record AutoCenterCatalogItemDto(
        [property: JsonPropertyName("erp_id")] int ErpId,
        [property: JsonPropertyName("name")] string Name,
        [property: JsonPropertyName("category")] string Category,
        [property: JsonPropertyName("price")] decimal Price,
        [property: JsonPropertyName("brand")] string Brand,
        [property: JsonPropertyName("code")] string Code,
        [property: JsonPropertyName("active")] bool Active
    );

    public sealed class SyncAutoCenterCatalogJob
    {
        private readonly FirebirdService _firebird;
        private readonly IHttpClientFactory _httpClientFactory;
        private readonly ILogger<SyncAutoCenterCatalogJob> _logger;
        private readonly StatusStore _status;
        private readonly SemaphoreSlim _lock = new(1, 1);

        public SyncAutoCenterCatalogJob(
            FirebirdService firebird,
            IHttpClientFactory httpClientFactory,
            ILogger<SyncAutoCenterCatalogJob> logger,
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
                _logger.LogInformation("[AutoCenterCatalogSync] Buscando catálogo no Firebird...");
                var rows = await _firebird.QueryAsync(@"
                    SELECT
                        P.ID_PRODUTO      AS erpId,
                        P.DESCRICAO       AS name,
                        TRIM(P.MARCA)     AS brand,
                        C.DESCRICAO       AS category,
                        P.REF             AS code,
                        PP.PRECO_TABELA   AS price
                    FROM PRODUTOS P
                    INNER JOIN PRODUTO_PRECOS PP
                        ON PP.ID_PRODUTO = P.ID_PRODUTO
                       AND PP.ATIVO = 1
                    LEFT JOIN CATEGORIAS C
                        ON C.ID_CATEGORIA = P.ID_CATEGORIA
                    WHERE COALESCE(P.BLOQUEADO, 0) = 0
                      AND P.TIPO = 2
                    ORDER BY P.DESCRICAO", ct: ct);

                if (rows.Count == 0)
                {
                    _logger.LogWarning("[AutoCenterCatalogSync] Nenhum produto encontrado.");
                    return;
                }

                var catalog = new List<AutoCenterCatalogItemDto>();
                foreach (var r in rows)
                {
                    try
                    {
                        int.TryParse(r.GetValueOrDefault("erpId")?.ToString(), out var erpId);
                        if (erpId == 0) continue;

                        var name = r.GetValueOrDefault("name")?.ToString() ?? "";
                        var brand = r.GetValueOrDefault("brand")?.ToString() ?? "";
                        var category = r.GetValueOrDefault("category")?.ToString() ?? "Geral";
                        var code = r.GetValueOrDefault("code")?.ToString() ?? erpId.ToString();
                        decimal.TryParse(r.GetValueOrDefault("price")?.ToString(), out var price);

                        catalog.Add(new AutoCenterCatalogItemDto(
                            erpId,
                            name,
                            category,
                            price,
                            brand,
                            code,
                            true // active by default
                        ));
                    }
                    catch (Exception ex)
                    {
                        _logger.LogWarning("[AutoCenterCatalogSync] Erro ao mapear linha de catálogo: {Err}", ex.Message);
                    }
                }

                if (catalog.Count == 0) return;

                _logger.LogInformation("[AutoCenterCatalogSync] Enviando {Count} itens de catálogo para o AutoCenter Middleware...", catalog.Count);
                
                var client = _httpClientFactory.CreateClient("AutoCenterApiClient");
                
                // Realiza POST para /internal/catalog/sync
                var res = await client.PostAsJsonAsync("/internal/catalog/sync", catalog, ct);

                if (res.IsSuccessStatusCode)
                {
                    _logger.LogInformation("[AutoCenterCatalogSync] Sincronização concluída com sucesso. {Count} itens enviados.", catalog.Count);
                    _status.AppendLog($"[{DateTime.Now:HH:mm:ss}] ✓ [AutoCenter] Catálogo Sincronizado: {catalog.Count}");
                    _status.Update("AutoCenter_Catalog", catalog.Count, DateTime.Now);
                }
                else
                {
                    var body = await res.Content.ReadAsStringAsync(ct);
                    _logger.LogError("[AutoCenterCatalogSync] Falha ao enviar catálogo para o middleware: {Status} | {Body}", res.StatusCode, body);
                    _status.Update("AutoCenter_Catalog", 0, DateTime.Now, $"HTTP {(int)res.StatusCode}");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError("[AutoCenterCatalogSync] Erro crítico no Sync de Catálogo: {Err}", ex.Message);
                _status.Update("AutoCenter_Catalog", 0, DateTime.Now, ex.Message);
            }
            finally
            {
                _lock.Release();
            }
        }
    }
}
