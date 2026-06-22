using System.Net.Http.Json;
using System.Text.Json;
using ColiseuSales.Worker.Config;
using ColiseuSales.Worker.Services;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace ColiseuSales.Worker.Jobs;

public sealed class SyncDashboardDataJob
{
    private readonly FirebirdService _firebird;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly IdentityApiOptions _identityOpts;
    private readonly DashboardApiOptions _dashOpts;
    private readonly StatusStore _store;
    private readonly DeltaCacheService _deltaCache;
    private readonly ILogger<SyncDashboardDataJob> _logger;
    private readonly ChangeTrackerService _changeTracker;

    public SyncDashboardDataJob(
        FirebirdService firebird,
        IHttpClientFactory httpClientFactory,
        IOptions<IdentityApiOptions> identityOpts,
        IOptions<DashboardApiOptions> dashOpts,
        StatusStore store,
        DeltaCacheService deltaCache,
        ILogger<SyncDashboardDataJob> logger,
        ChangeTrackerService changeTracker)
    {
        _firebird = firebird;
        _httpClientFactory = httpClientFactory;
        _identityOpts = identityOpts.Value;
        _dashOpts = dashOpts.Value;
        _store = store;
        _deltaCache = deltaCache;
        _logger = logger;
        _changeTracker = changeTracker;
    }

    public async Task RunAsync(bool force = false, CancellationToken ct = default)
    {
        if (!_dashOpts.Enabled)
        {
            _logger.LogDebug("[Dashboard Sync] Desabilitado no appsettings");
            _store.Update("DashboardData", 0, DateTime.Now, "Desativado");
            return;
        }

        if (!await _firebird.IsAvailableAsync(ct))
        {
            _logger.LogWarning("[Dashboard Sync] Conexão com Firebird ausente. Abortando sync.");
            await SendHeartbeatAsync("FIREBIRD_OFFLINE", ct);
            return;
        }

        var tables = new[] { "CLIENTES", "PRODUTOS", "FUNCIONARIOS", "PEDIDOS", "CONTAS", "CAIXAS", "DEPARTAMENTOS" };
        if (!force && !await _changeTracker.HasChangesAsync("DashboardSync", tables))
        {
            _logger.LogDebug("[Dashboard Sync] Sem alterações no Firebird. Ignorando este ciclo.");
            await SendHeartbeatAsync("OK", ct);
            return;
        }

        _logger.LogInformation("[Dashboard Sync] Iniciando ciclo de sincronização...");
        _store.AppendLog($"[{DateTime.Now:HH:mm:ss}] === Coliseu Dash: Iniciando sync ===");

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

            await SendHeartbeatAsync("OK", ct);
            _logger.LogInformation("[Dashboard Sync] Ciclo concluído com sucesso.");
            _store.AppendLog($"[{DateTime.Now:HH:mm:ss}] === Coliseu Dash: Sync finalizado ===");
            await _changeTracker.UpdateLastProcessedLogIdAsync("DashboardSync", tables);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[Dashboard Sync] Erro global durante ciclo de sincronização.");
            _store.AppendLog($"[{DateTime.Now:HH:mm:ss}] ⚠ Coliseu Dash: Erro global - {ex.Message}");
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
            _store.Update("Dash_Clientes", 0, DateTime.Now, "Falha ao buscar no Firebird");
            return;
        }

        await PushToMiddlewareAsync("dash_clientes", "Dash_Clientes", data, ct);
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
            _store.Update("Dash_Produtos", 0, DateTime.Now, "Falha ao buscar no Firebird");
            return;
        }

        await PushToMiddlewareAsync("dash_produtos", "Dash_Produtos", data, ct);
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
            _store.Update("Dash_Vendedores", 0, DateTime.Now, "Falha ao buscar no Firebird");
            return;
        }

        await PushToMiddlewareAsync("dash_vendedores", "Dash_Vendedores", data, ct);
    }

    private async Task SyncVendasAsync(CancellationToken ct)
    {
        // Otimização: A view DASH_VENDAS tem um GROUP BY. 
        // Em Firebird, um ORDER BY DESC + FIRST N em uma view com GROUP BY 
        // força o full table scan antes de ordenar. 
        // Adicionamos um filtro no ID para reduzir drasticamente o escopo agregado.
        var sql = @"
            SELECT *
            FROM DASH_VENDAS
            ORDER BY id_firebird DESC
        ";

        var (success, data) = await _firebird.QueryRawAsync(sql);
        if (!success || data == null)
        {
            _store.Update("Dash_Vendas", 0, DateTime.Now, "Falha ao buscar no Firebird");
            return;
        }

        await PushToMiddlewareAsync("dash_vendas", "Dash_Vendas", data, ct);
    }

    private async Task SyncVendasItensAsync(CancellationToken ct)
    {
        // Agora utilizando a view customizada criada no FirebirdBootstrapper
        var sql = @"
            SELECT *
            FROM DASH_VENDAS_ITENS
            ORDER BY venda_id_firebird DESC
        ";

        var (success, data) = await _firebird.QueryRawAsync(sql);
        if (!success || data == null)
        {
            _store.Update("Dash_Vendas_Itens", 0, DateTime.Now, "Falha ao buscar no Firebird");
            return;
        }

        await PushToMiddlewareAsync("dash_vendas_itens", "Dash_Vendas_Itens", data, ct);
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
            _store.Update("Dash_Caixas", 0, DateTime.Now, "Falha ao buscar no Firebird");
            return;
        }

        int count = data.Count;
        if (count == 0)
        {
            _store.Update("Dash_Caixas", 0, DateTime.Now, "Nenhum registro encontrado");
            return;
        }

        await PushToMiddlewareAsync("dash_caixas", "Dash_Caixas", data, ct);
    }

    private async Task SyncFinanceiroAsync(CancellationToken ct)
    {
        // Otimização de Performance para views pesadas do Firebird
        var sql = @"
            SELECT *
            FROM DASH_FINANCEIRO
            ORDER BY id_firebird DESC
        ";

        var (success, data) = await _firebird.QueryRawAsync(sql);
        if (!success || data == null)
        {
            _store.Update("Dash_Financeiro", 0, DateTime.Now, "Falha ao buscar no Firebird");
            return;
        }

        await PushToMiddlewareAsync("dash_financeiro", "Dash_Financeiro", data, ct);
    }

    private async Task SyncFiliaisAsync(CancellationToken ct)
    {
        // Lê a view DASH_FILIAIS criada pelo FirebirdBootstrapper (Preparar Banco)
        // Popula dash_filiais no Postgres — habilita o BranchSelector no frontend
        var sql = @"
            SELECT *
            FROM DASH_FILIAIS
        ";

        var (success, data) = await _firebird.QueryRawAsync(sql);
        if (!success || data == null)
        {
            _logger.LogWarning("[Dashboard Sync] DASH_FILIAIS: view não encontrada. Execute 'Preparar Banco' no Configurator.");
            _store.Update("Dash_Filiais", 0, DateTime.Now, "View DASH_FILIAIS não encontrada");
            return;
        }

        if (data.Count == 0)
        {
            _store.Update("Dash_Filiais", 0, DateTime.Now, "Nenhuma filial ativa");
            return;
        }

        await PushToMiddlewareAsync("dash_filiais", "Dash_Filiais", data, ct);
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
                // Busca id_firebird, suportando minúsculo ou maiúsculo
                var idObj = row.FirstOrDefault(k => string.Equals(k.Key, "id_firebird", StringComparison.OrdinalIgnoreCase)).Value;
                
                if (idObj == null)
                {
                    // Caso excepcional onde não há id_firebird, manda sempre.
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
            // Nenhum dado mudou
            _logger.LogInformation("[Dashboard Sync] {Key} -> Tudo atualizado ({Count} verificados, 0 mudanças)", storeLabel, rawRows.Count);
            _store.Update(storeLabel, rawRows.Count, DateTime.Now);
            _store.AppendLog($"[{DateTime.Now:HH:mm:ss}] ✓ [Dash] {storeLabel}: Sem mudanças ({rawRows.Count} analisados)");
            return;
        }

        _logger.LogInformation("[Dashboard Sync] {Key} -> Delta: enviando {NewCount} alterações (de {TotalCount} total)", storeLabel, rowsToPush.Count, rawRows.Count);

        try
        {
            var client = _httpClientFactory.CreateClient("DashboardApiClient");
            client.DefaultRequestHeaders.Add("X-Tenant-Id", _identityOpts.TenantId.ToString());

            // Processar em batches de 250 para evitar 413 Payload Too Large no Nginx do VPS
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
                    _logger.LogError("[Dashboard Sync] Falha no push. Status: {Status}, Endpoint: {Endpoint}, Res: {Msg}", response.StatusCode, endpoint, msg);
                    _store.Update(storeLabel, rawRows.Count, DateTime.Now, $"HTTP {(int)response.StatusCode} - {shortMsg}");
                    _store.AppendLog($"[{DateTime.Now:HH:mm:ss}] ✗ [Dash] {storeLabel}: erro HTTP {(int)response.StatusCode} - {shortMsg}");
                    return;
                }

                // Lê a resposta JSON para verificar se o Postgres rejeitou as linhas
                var result = await response.Content.ReadFromJsonAsync<JsonElement>(cancellationToken: ct);
                if (result.TryGetProperty("erros", out var errosProp) && errosProp.GetInt32() > 0)
                {
                    var msgErro = "Desconhecido";
                    if (result.TryGetProperty("detalhes", out var detalhesProp) && detalhesProp.GetArrayLength() > 0)
                    {
                        msgErro = detalhesProp[0].GetString();
                    }
                    _logger.LogError("[Dashboard Sync] Middleware retornou erro no banco de dados para {Endpoint}: {Erro}", endpoint, msgErro);
                    _store.Update(storeLabel, rawRows.Count, DateTime.Now, "Erro interno no BD do Middleware");
                    _store.AppendLog($"[{DateTime.Now:HH:mm:ss}] ✗ [Dash] {storeLabel}: erro SQL - {msgErro}");
                    return;
                }
                else
                {
                    _logger.LogInformation("[Dashboard Sync] Lote de {Count} registros enviados para {Endpoint}", batch.Count, endpoint);
                    
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
            _store.AppendLog($"[{DateTime.Now:HH:mm:ss}] ✓ [Dash] {storeLabel}: {rowsToPush.Count} enviados / {rawRows.Count} verificados");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[Dashboard Sync] Erro ao comunicar com Dashboard Middleware para endpoint {Endpoint}", endpoint);
            _store.Update(storeLabel, rawRows.Count, DateTime.Now, ex.Message);
            _store.AppendLog($"[{DateTime.Now:HH:mm:ss}] ⚠ [Dash] Erro comunicação {storeLabel}: {ex.Message}");
        }
    }

    private async Task SendHeartbeatAsync(string status, CancellationToken ct)
    {
        try
        {
            var client = _httpClientFactory.CreateClient("DashboardApiClient");
            client.DefaultRequestHeaders.Add("X-Tenant-Id", _identityOpts.TenantId.ToString());

            var response = await client.PostAsJsonAsync("/internal/sync/heartbeat", new { status = status }, ct);
            if (response.IsSuccessStatusCode)
            {
                _logger.LogInformation("[Dashboard Sync] Heartbeat enviado com sucesso: {Status}", status);
            }
            else
            {
                _logger.LogWarning("[Dashboard Sync] Falha ao enviar Heartbeat. Status: {Code}", response.StatusCode);
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning("[Dashboard Sync] Erro ao enviar Heartbeat: {Msg}", ex.Message);
        }
    }
}
