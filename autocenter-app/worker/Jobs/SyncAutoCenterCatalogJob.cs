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
    public record AutoCenterCatalogItemDto(
        [property: JsonPropertyName("erp_id")] int ErpId,
        [property: JsonPropertyName("name")] string Name,
        [property: JsonPropertyName("category")] string Category,
        [property: JsonPropertyName("price")] decimal Price,
        [property: JsonPropertyName("brand")] string Brand,
        [property: JsonPropertyName("code")] string Code,
        [property: JsonPropertyName("active")] bool Active
    );

    public record AutoCenterPaymentSpeciesDto(
        [property: JsonPropertyName("id")] int Id,
        [property: JsonPropertyName("descricao")] string Descricao,
        [property: JsonPropertyName("tipo")] string Tipo,
        [property: JsonPropertyName("active")] bool Active
    );

    public record AutoCenterPaymentConditionDto(
        [property: JsonPropertyName("id")] string Id,
        [property: JsonPropertyName("especieId")] int EspecieId,
        [property: JsonPropertyName("formaId")] int FormaId,
        [property: JsonPropertyName("descricao")] string Descricao,
        [property: JsonPropertyName("active")] bool Active
    );

    public record AutoCenterNaturezaDto(
        [property: JsonPropertyName("id")] int Id,
        [property: JsonPropertyName("descricao")] string Descricao,
        [property: JsonPropertyName("descricaoNota")] string DescricaoNota,
        [property: JsonPropertyName("codigoFiscal")] string CodigoFiscal,
        [property: JsonPropertyName("es")] int Es,
        [property: JsonPropertyName("processo")] int Processo,
        [property: JsonPropertyName("tipo")] int Tipo,
        [property: JsonPropertyName("mobOrdem")] int MobOrdem,
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

                // Sincroniza as configurações adicionais do ERP
                await SyncPaymentSpeciesAsync(client, ct);
                await SyncPaymentConditionsAsync(client, ct);
                await SyncNaturezasOperacaoAsync(client, ct);
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

        private async Task SyncPaymentSpeciesAsync(HttpClient client, CancellationToken ct)
        {
            try
            {
                _logger.LogInformation("[AutoCenterPaymentSpeciesSync] Buscando espécies de pagamento no Firebird...");
                var rows = await _firebird.QueryAsync(@"
                    SELECT E.ID_ESPECIE AS id,
                           TRIM(E.DESCRICAO) AS descricao,
                           E.TIPO AS tipo
                    FROM ESPECIE_PGTO E
                    WHERE E.MOB_ACESSO = 1
                    ORDER BY E.DESCRICAO", ct: ct);

                var list = new List<AutoCenterPaymentSpeciesDto>();
                foreach (var r in rows)
                {
                    int.TryParse(r.GetValueOrDefault("id")?.ToString(), out var id);
                    if (id == 0) continue;
                    var desc = r.GetValueOrDefault("descricao")?.ToString() ?? "";
                    var tipo = r.GetValueOrDefault("tipo")?.ToString() ?? "";
                    list.Add(new AutoCenterPaymentSpeciesDto(id, desc, tipo, true));
                }

                if (list.Count == 0) return;

                _logger.LogInformation("[AutoCenterPaymentSpeciesSync] Enviando {Count} espécies para o AutoCenter Middleware...", list.Count);
                var res = await client.PostAsJsonAsync("/internal/payment-species/sync", list, ct);
                if (res.IsSuccessStatusCode)
                {
                    _logger.LogInformation("[AutoCenterPaymentSpeciesSync] Sincronização concluída com sucesso.");
                    _status.Update("AutoCenter_PaymentSpecies", list.Count, DateTime.Now);
                }
                else
                {
                    var body = await res.Content.ReadAsStringAsync(ct);
                    _logger.LogError("[AutoCenterPaymentSpeciesSync] Falha: {Status} | {Body}", res.StatusCode, body);
                    _status.Update("AutoCenter_PaymentSpecies", 0, DateTime.Now, $"HTTP {(int)res.StatusCode}");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError("[AutoCenterPaymentSpeciesSync] Erro: {Err}", ex.Message);
                _status.Update("AutoCenter_PaymentSpecies", 0, DateTime.Now, ex.Message);
            }
        }

        private async Task SyncPaymentConditionsAsync(HttpClient client, CancellationToken ct)
        {
            try
            {
                _logger.LogInformation("[AutoCenterPaymentConditionsSync] Buscando condições de pagamento no Firebird...");
                var rows = await _firebird.QueryAsync(@"
                    SELECT (F.ID_FORMA || '_' || FP.ID_ESPECIE) AS id,
                           FP.ID_ESPECIE AS especieId,
                           F.ID_FORMA AS formaId,
                           TRIM(F.DESCRICAO) AS descricao
                    FROM FORMA_PGTO F
                    INNER JOIN FORMA_PGTO_PERMISSAO FP ON FP.ID_FORMA = F.ID_FORMA
                    INNER JOIN ESPECIE_PGTO E ON E.ID_ESPECIE = FP.ID_ESPECIE
                    WHERE F.MOB_ACESSO = 1 AND E.MOB_ACESSO = 1
                    ORDER BY F.DESCRICAO", ct: ct);

                var list = new List<AutoCenterPaymentConditionDto>();
                foreach (var r in rows)
                {
                    var id = r.GetValueOrDefault("id")?.ToString() ?? "";
                    if (string.IsNullOrEmpty(id)) continue;
                    int.TryParse(r.GetValueOrDefault("especieId")?.ToString(), out var especieId);
                    int.TryParse(r.GetValueOrDefault("formaId")?.ToString(), out var formaId);
                    var desc = r.GetValueOrDefault("descricao")?.ToString() ?? "";
                    list.Add(new AutoCenterPaymentConditionDto(id, especieId, formaId, desc, true));
                }

                if (list.Count == 0) return;

                _logger.LogInformation("[AutoCenterPaymentConditionsSync] Enviando {Count} condições para o AutoCenter Middleware...", list.Count);
                var res = await client.PostAsJsonAsync("/internal/payment-conditions/sync", list, ct);
                if (res.IsSuccessStatusCode)
                {
                    _logger.LogInformation("[AutoCenterPaymentConditionsSync] Sincronização concluída com sucesso.");
                    _status.Update("AutoCenter_PaymentConditions", list.Count, DateTime.Now);
                }
                else
                {
                    var body = await res.Content.ReadAsStringAsync(ct);
                    _logger.LogError("[AutoCenterPaymentConditionsSync] Falha: {Status} | {Body}", res.StatusCode, body);
                    _status.Update("AutoCenter_PaymentConditions", 0, DateTime.Now, $"HTTP {(int)res.StatusCode}");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError("[AutoCenterPaymentConditionsSync] Erro: {Err}", ex.Message);
                _status.Update("AutoCenter_PaymentConditions", 0, DateTime.Now, ex.Message);
            }
        }

        private async Task SyncNaturezasOperacaoAsync(HttpClient client, CancellationToken ct)
        {
            try
            {
                _logger.LogInformation("[AutoCenterNaturezasSync] Buscando naturezas de operação no Firebird...");
                var rows = await _firebird.QueryAsync(@"
                    SELECT N.ID_NATUREZA       AS id,
                           TRIM(N.DESCRICAO)   AS descricao,
                           TRIM(N.DESCRICAO_NOTA) AS descricaoNota,
                           N.CODIGO_FISCAL     AS codigoFiscal,
                           N.ES                AS es,
                           N.PROCESSO          AS processo,
                           N.TIPO              AS tipo,
                           N.MOB_ORDEM         AS mobOrdem
                    FROM NATUREZA_OPERACAO N
                    WHERE N.MOB_ACESSO = 1
                    ORDER BY N.MOB_ORDEM ASC, N.DESCRICAO ASC", ct: ct);

                var list = new List<AutoCenterNaturezaDto>();
                foreach (var r in rows)
                {
                    int.TryParse(r.GetValueOrDefault("id")?.ToString(), out var id);
                    if (id == 0) continue;
                    var desc = r.GetValueOrDefault("descricao")?.ToString() ?? "";
                    var descNota = r.GetValueOrDefault("descricaoNota")?.ToString() ?? "";
                    var cf = r.GetValueOrDefault("codigoFiscal")?.ToString() ?? "";
                    int.TryParse(r.GetValueOrDefault("es")?.ToString(), out var es);
                    int.TryParse(r.GetValueOrDefault("processo")?.ToString(), out var proc);
                    int.TryParse(r.GetValueOrDefault("tipo")?.ToString(), out var tipo);
                    int.TryParse(r.GetValueOrDefault("mobOrdem")?.ToString(), out var ord);
                    list.Add(new AutoCenterNaturezaDto(id, desc, descNota, cf, es, proc, tipo, ord, true));
                }

                if (list.Count == 0) return;

                _logger.LogInformation("[AutoCenterNaturezasSync] Enviando {Count} naturezas para o AutoCenter Middleware...", list.Count);
                var res = await client.PostAsJsonAsync("/internal/naturezas/sync", list, ct);
                if (res.IsSuccessStatusCode)
                {
                    _logger.LogInformation("[AutoCenterNaturezasSync] Sincronização concluída com sucesso.");
                    _status.Update("AutoCenter_Naturezas", list.Count, DateTime.Now);
                }
                else
                {
                    var body = await res.Content.ReadAsStringAsync(ct);
                    _logger.LogError("[AutoCenterNaturezasSync] Falha: {Status} | {Body}", res.StatusCode, body);
                    _status.Update("AutoCenter_Naturezas", 0, DateTime.Now, $"HTTP {(int)res.StatusCode}");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError("[AutoCenterNaturezasSync] Erro: {Err}", ex.Message);
                _status.Update("AutoCenter_Naturezas", 0, DateTime.Now, ex.Message);
            }
        }
    }
}
