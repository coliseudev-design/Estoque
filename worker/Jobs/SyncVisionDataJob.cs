using System.Net.Http.Json;
using System.Text.Json;
using ColiseuSpeed.Worker.Config;
using ColiseuSpeed.Worker.Services;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace ColiseuSpeed.Worker.Jobs;

public sealed class SyncVisionDataJob
{
    private readonly FirebirdService _firebird;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly IdentityApiOptions _identityOpts;
    private readonly VisionApiOptions _visionOpts;
    private readonly StatusStore _store;
    private readonly DeltaCacheService _deltaCache;
    private readonly ILogger<SyncVisionDataJob> _logger;
    private readonly ChangeTrackerService _changeTracker;

    public SyncVisionDataJob(
        FirebirdService firebird,
        IHttpClientFactory httpClientFactory,
        IOptions<IdentityApiOptions> identityOpts,
        IOptions<VisionApiOptions> visionOpts,
        StatusStore store,
        DeltaCacheService deltaCache,
        ILogger<SyncVisionDataJob> logger,
        ChangeTrackerService changeTracker)
    {
        _firebird = firebird;
        _httpClientFactory = httpClientFactory;
        _identityOpts = identityOpts.Value;
        _visionOpts = visionOpts.Value;
        _store = store;
        _deltaCache = deltaCache;
        _logger = logger;
        _changeTracker = changeTracker;
    }

    public async Task RunAsync(bool force = false, CancellationToken ct = default)
    {
        if (!_visionOpts.Enabled)
        {
            _logger.LogDebug("[Vision Sync] Desabilitado no appsettings");
            _store.Update("VisionData", 0, DateTime.Now, "Desativado");
            return;
        }

        var tables = new[] { "CLIENTES", "PRODUTOS", "FUNCIONARIOS", "PEDIDOS", "CONTAS", "CAIXAS", "DEPARTAMENTOS" };
        if (!force && !await _changeTracker.HasChangesAsync("VisionSync", tables))
        {
            _logger.LogDebug("[Vision Sync] Sem alterações no Firebird. Ignorando este ciclo.");
            return;
        }

        if (!await _firebird.IsAvailableAsync(ct))
        {
            _logger.LogWarning("[Vision Sync] Conexão com Firebird ausente. Abortando sync.");
            return;
        }

        _logger.LogInformation("[Vision Sync] Iniciando ciclo de sincronização...");
        _store.AppendLog($"[{DateTime.Now:HH:mm:ss}] === Vision: Iniciando sync ===");

        try
        {
            await SyncClientesAsync(ct);
            await SyncProdutosAsync(ct);
            await SyncVendedoresAsync(ct);
            await SyncVendasAsync(ct);
            await SyncVendasItensAsync(ct);
            await SyncCaixasAsync(ct);
            await SyncFinanceiroAsync(ct);
            await SyncFiliaisAsync(ct);

            _logger.LogInformation("[Vision Sync] Ciclo concluído com sucesso.");
            _store.AppendLog($"[{DateTime.Now:HH:mm:ss}] === Vision: Sync finalizado ===");
            await _changeTracker.UpdateLastProcessedLogIdAsync("VisionSync", tables);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[Vision Sync] Erro global durante ciclo de sincronização.");
            _store.AppendLog($"[{DateTime.Now:HH:mm:ss}] ⚠ Vision: Erro global - {ex.Message}");
        }
    }

    private async Task SyncClientesAsync(CancellationToken ct)
    {
        var sql = @"
            SELECT *
            FROM DASH_CLIENTES
            ORDER BY id_firebird DESC
        ";

        var (success, data) = await _firebird.QueryRawAsync(sql);
        if (!success || data == null)
        {
            _store.Update("Vision_Clientes", 0, DateTime.Now, "Falha ao buscar no Firebird");
            return;
        }

        await PushToMiddlewareAsync("dash_clientes", "Vision_Clientes", data, ct);
    }

    private async Task SyncProdutosAsync(CancellationToken ct)
    {
        var sql = @"
            SELECT *
            FROM DASH_PRODUTOS
            ORDER BY id_firebird DESC
        ";

        var (success, data) = await _firebird.QueryRawAsync(sql);
        if (!success || data == null)
        {
            _store.Update("Vision_Produtos", 0, DateTime.Now, "Falha ao buscar no Firebird");
            return;
        }

        await PushToMiddlewareAsync("dash_produtos", "Vision_Produtos", data, ct);
    }

    private async Task SyncVendedoresAsync(CancellationToken ct)
    {
        var sql = @"
            SELECT *
            FROM DASH_VENDEDORES
        ";

        var (success, data) = await _firebird.QueryRawAsync(sql);
        if (!success || data == null)
        {
            _store.Update("Vision_Vendedores", 0, DateTime.Now, "Falha ao buscar no Firebird");
            return;
        }

        await PushToMiddlewareAsync("dash_vendedores", "Vision_Vendedores", data, ct);
    }

    private async Task SyncVendasAsync(CancellationToken ct)
    {
        var sql = @"
            SELECT *
            FROM DASH_VENDAS
            WHERE id_firebird >= (SELECT COALESCE(MAX(ID_PEDIDO), 0) - 50000 FROM PEDIDOS)
            ORDER BY id_firebird DESC
        ";

        var (success, data) = await _firebird.QueryRawAsync(sql);
        if (!success || data == null)
        {
            _store.Update("Vision_Vendas", 0, DateTime.Now, "Falha ao buscar no Firebird");
            return;
        }

        await PushToMiddlewareAsync("dash_vendas", "Vision_Vendas", data, ct);
    }

    private async Task SyncVendasItensAsync(CancellationToken ct)
    {
        var sql = @"
            SELECT *
            FROM DASH_VENDAS_ITENS
            ORDER BY venda_id_firebird DESC
        ";

        var (success, data) = await _firebird.QueryRawAsync(sql);
        if (!success || data == null)
        {
            _store.Update("Vision_Vendas_Itens", 0, DateTime.Now, "Falha ao buscar no Firebird");
            return;
        }

        await PushToMiddlewareAsync("dash_vendas_itens", "Vision_Vendas_Itens", data, ct);
    }

    private async Task SyncCaixasAsync(CancellationToken ct)
    {
        var sql = @"
            SELECT
                ID_CAIXA AS id_firebird,
                DESCRICAO AS descricao
            FROM CAIXAS
        ";

        var (success, data) = await _firebird.QueryRawAsync(sql);
        if (!success || data == null)
        {
            _store.Update("Vision_Caixas", 0, DateTime.Now, "Falha ao buscar no Firebird");
            return;
        }

        int count = data.Count;
        if (count == 0)
        {
            _store.Update("Vision_Caixas", 0, DateTime.Now, "Nenhum registro encontrado");
            return;
        }

        await PushToMiddlewareAsync("dash_caixas", "Vision_Caixas", data, ct);
    }

    private async Task SyncFinanceiroAsync(CancellationToken ct)
    {
        var sql = @"
            SELECT *
            FROM DASH_FINANCEIRO
            WHERE id_firebird >= (SELECT COALESCE(MAX(ID_CONTA), 0) - 50000 FROM CONTAS)
            ORDER BY id_firebird DESC
        ";

        var (success, data) = await _firebird.QueryRawAsync(sql);
        if (!success || data == null)
        {
            _store.Update("Vision_Financeiro", 0, DateTime.Now, "Falha ao buscar no Firebird");
            return;
        }

        await PushToMiddlewareAsync("dash_financeiro", "Vision_Financeiro", data, ct);
    }

    private async Task SyncFiliaisAsync(CancellationToken ct)
    {
        var sql = @"
            SELECT *
            FROM DASH_FILIAIS
        ";

        var (success, data) = await _firebird.QueryRawAsync(sql);
        if (!success || data == null)
        {
            _logger.LogWarning("[Vision Sync] DASH_FILIAIS: view não encontrada. Execute 'Preparar Banco' no Configurator.");
            _store.Update("Vision_Filiais", 0, DateTime.Now, "View DASH_FILIAIS não encontrada");
            return;
        }

        if (data.Count == 0)
        {
            _store.Update("Vision_Filiais", 0, DateTime.Now, "Nenhuma filial ativa");
            return;
        }

        await PushToMiddlewareAsync("dash_filiais", "Vision_Filiais", data, ct);
    }

    private async Task PushToMiddlewareAsync(string endpoint, string storeLabel, IEnumerable<Dictionary<string, object?>> data, CancellationToken ct)
    {
        var rawRows = data.ToList();
        if (rawRows.Count == 0) return;

        var rowsToPush = new List<Dictionary<string, object?>>();
        var hashesToSave = new Dictionary<string, string>();

        // Carrega todos os hashes cadastrados para esta entidade na memória
        var cachedHashes = _deltaCache.GetEntityHashes(storeLabel);

        foreach (var row in rawRows)
        {
            try
            {
                var idObj = row.FirstOrDefault(k => string.Equals(k.Key, "id_firebird", StringComparison.OrdinalIgnoreCase)).Value;
                
                if (idObj == null)
                {
                    rowsToPush.Add(row);
                    continue;
                }

                string idFirebird = idObj.ToString()!;
                string hash = _deltaCache.ComputeHash(row);

                // Compara em memória em vez de fazer query individual no banco
                if (!cachedHashes.TryGetValue(idFirebird, out var savedHash) || savedHash != hash)
                {
                    rowsToPush.Add(row);
                    hashesToSave[idFirebird] = hash;
                }
            }
            catch (Exception)
            {
                rowsToPush.Add(row);
            }
        }

        if (rowsToPush.Count == 0)
        {
            _logger.LogInformation("[Vision Sync] {Key} -> Tudo atualizado ({Count} verificados, 0 mudanças)", storeLabel, rawRows.Count);
            _store.Update(storeLabel, rawRows.Count, DateTime.Now);
            _store.AppendLog($"[{DateTime.Now:HH:mm:ss}] ✓ [Vision] {storeLabel}: Sem mudanças ({rawRows.Count} analisados)");
            return;
        }

        _logger.LogInformation("[Vision Sync] {Key} -> Delta: enviando {NewCount} alterações (de {TotalCount} total)", storeLabel, rowsToPush.Count, rawRows.Count);

        try
        {
            var client = _httpClientFactory.CreateClient("VisionApiClient");
            client.DefaultRequestHeaders.Add("X-Tenant-Id", _identityOpts.TenantId.ToString());

            var batchSize = 250;
            for (int i = 0; i < rowsToPush.Count; i += batchSize)
            {
                ct.ThrowIfCancellationRequested();
                var batch = rowsToPush.Skip(i).Take(batchSize).ToList();

                var response = await client.PostAsJsonAsync($"/internal/sync/{endpoint}", new { rows = batch }, ct);
                
                if (!response.IsSuccessStatusCode)
                {
                    var msg = await response.Content.ReadAsStringAsync(ct);
                    var shortMsg = msg.Length > 100 ? msg.Substring(0, 100) + "..." : msg;
                    _logger.LogError("[Vision Sync] Falha no push. Status: {Status}, Endpoint: {Endpoint}, Res: {Msg}", response.StatusCode, endpoint, msg);
                    _store.Update(storeLabel, rawRows.Count, DateTime.Now, $"HTTP {(int)response.StatusCode} - {shortMsg}");
                    _store.AppendLog($"[{DateTime.Now:HH:mm:ss}] ✗ [Vision] {storeLabel}: erro HTTP {(int)response.StatusCode} - {shortMsg}");
                    return;
                }

                var result = await response.Content.ReadFromJsonAsync<JsonElement>(cancellationToken: ct);
                if (result.TryGetProperty("erros", out var errosProp) && errosProp.GetInt32() > 0)
                {
                    var msgErro = "Desconhecido";
                    if (result.TryGetProperty("detalhes", out var detalhesProp) && detalhesProp.GetArrayLength() > 0)
                    {
                        msgErro = detalhesProp[0].GetString();
                    }
                    _logger.LogError("[Vision Sync] Middleware retornou erro no banco de dados para {Endpoint}: {Erro}", endpoint, msgErro);
                    _store.Update(storeLabel, rawRows.Count, DateTime.Now, "Erro interno no BD do Middleware");
                    _store.AppendLog($"[{DateTime.Now:HH:mm:ss}] ✗ [Vision] {storeLabel}: erro SQL - {msgErro}");
                    return;
                }
                else
                {
                    _logger.LogInformation("[Vision Sync] Lote de {Count} registros enviados para {Endpoint}", batch.Count, endpoint);
                    
                    // Coleta hashes do lote atual sincronizado e salva em lote (transação única) no SQLite
                    var batchHashes = new Dictionary<string, string>();
                    foreach (var row in batch)
                    {
                        var idObj = row.FirstOrDefault(k => string.Equals(k.Key, "id_firebird", StringComparison.OrdinalIgnoreCase)).Value;
                        if (idObj != null)
                        {
                            string idFirebird = idObj.ToString()!;
                            if (hashesToSave.TryGetValue(idFirebird, out var hash))
                            {
                                batchHashes[idFirebird] = hash;
                            }
                        }
                    }
                    _deltaCache.SaveHashes(storeLabel, batchHashes);
                }
            }

            _store.Update(storeLabel, rawRows.Count, DateTime.Now);
            _store.AppendLog($"[{DateTime.Now:HH:mm:ss}] ✓ [Vision] {storeLabel}: {rowsToPush.Count} enviados / {rawRows.Count} verificados");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[Vision Sync] Erro ao comunicar com Vision Middleware para endpoint {Endpoint}", endpoint);
            _store.Update(storeLabel, rawRows.Count, DateTime.Now, ex.Message);
            _store.AppendLog($"[{DateTime.Now:HH:mm:ss}] ⚠ [Vision] Erro comunicação {storeLabel}: {ex.Message}");
        }
    }
}
