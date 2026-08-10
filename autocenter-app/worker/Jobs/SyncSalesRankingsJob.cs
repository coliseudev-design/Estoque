using ColiseuSales.Worker.Services;

namespace ColiseuSales.Worker.Jobs;

/// <summary>
/// SyncSalesRankingsJob — Sincroniza rankings de vendas do ERP (Firebird → VPS).
///
/// Lê as views L_VENDAS_PRODUTO, L_VENDAS_CLIENTE e L_VENDAS_REGIAO
/// com queries agregadas filtradas por vendedor e período do mês atual.
///
/// Cadência: roda junto com o CatalogSync (a cada CatalogSyncIntervalMinutes).
/// Rule-02: totalmente async.
/// </summary>
public sealed class SyncSalesRankingsJob
{
    private readonly FirebirdService                  _firebird;
    private readonly VpsApiClient                     _vps;
    private readonly StatusStore                      _status;
    private readonly ILogger<SyncSalesRankingsJob>    _logger;

    public SyncSalesRankingsJob(
        FirebirdService                 firebird,
        VpsApiClient                    vps,
        StatusStore                     status,
        ILogger<SyncSalesRankingsJob>   logger)
    {
        _firebird = firebird;
        _vps      = vps;
        _status   = status;
        _logger   = logger;
    }

    /// <summary>
    /// Executa a sincronização dos rankings de vendas para todos os vendedores ativos.
    /// </summary>
    public async Task RunAsync(CancellationToken ct = default)
    {
        _logger.LogDebug("[SalesRankings] Iniciando sincronização de rankings...");

        try
        {
            // 1. Busca vendedores ativos
            var sellers = await _firebird.QueryAsync(
                "SELECT ID_FUNCIONARIO, NOME FROM FUNCIONARIOS WHERE MOB_ACESSO = 1",
                ct: ct);

            if (sellers.Count == 0)
            {
                _status.Update("SalesRankings", 0, DateTime.Now, "Nenhum vendedor ativo");
                return;
            }

            _logger.LogInformation("[SalesRankings] {Count} vendedores encontrados", sellers.Count);

            var now = DateTime.Now;

            // 2. Define 4 períodos: today, week, month, all
            // IMPORTANTE: Firebird trata 'yyyy-MM-dd' como '00:00:00.000' em TIMESTAMP.
            // Por isso o lastDay termina em ' 23:59:59' para capturar todos os registros do dia.
            var periods = new (string period, string firstDay, string lastDay)[]
            {
                ("today", now.ToString("yyyy-MM-dd 00:00:00"),
                           now.ToString("yyyy-MM-dd 23:59:59")),
                ("week",  now.AddDays(-7).ToString("yyyy-MM-dd 00:00:00"),
                           now.ToString("yyyy-MM-dd 23:59:59")),
                ("month", new DateTime(now.Year, now.Month, 1).ToString("yyyy-MM-dd 00:00:00"),
                          now.ToString("yyyy-MM-dd 23:59:59")),
                ("all",   now.AddDays(-365).ToString("yyyy-MM-dd 00:00:00"),
                           now.ToString("yyyy-MM-dd 23:59:59")),
            };

            var allRankings = new List<object>();
            var errors = new List<string>();
            int successCount = 0;

            foreach (var seller in sellers)
            {
                var sellerId = Convert.ToInt32(seller["ID_FUNCIONARIO"]);
                _logger.LogInformation("[SalesRankings] Processando vendedor {Id}...", sellerId);

                foreach (var (period, firstDay, lastDay) in periods)
                {
                    try
                    {
                        var rankings = await BuildSellerRankingsAsync(
                            sellerId, firstDay, lastDay, now, period, ct);
                        allRankings.Add(rankings);
                        successCount++;
                    }
                    catch (Exception ex)
                    {
                        var errorDetail = $"V{sellerId}/{period}: {ex.Message}";
                        errors.Add(errorDetail);
                        _logger.LogWarning(
                            "[SalesRankings] Erro vendedor {Id} período {Period}: {Error}",
                            sellerId, period, ex.Message);
                    }
                }

                _logger.LogInformation("[SalesRankings] Vendedor {Id} OK", sellerId);
            }

            // Diagnóstico: monta status descritivo
            var diag = $"S={sellers.Count} P=4 OK={successCount} ERR={errors.Count}";

            if (allRankings.Count > 0)
            {
                var ok = await _vps.PushSalesRankingsAsync(allRankings, ct);
                _logger.LogInformation(
                    "[SalesRankings] {Count} itens sincronizados ({Sellers}×4). Push={Ok}",
                    allRankings.Count, sellers.Count, ok);
                _status.Update("SalesRankings", allRankings.Count, DateTime.Now,
                    ok ? null : $"Push falhou ({diag})");
            }
            else
            {
                var errorMsg = errors.Count > 0
                    ? $"{diag} | {errors[0]}"
                    : $"Zero rankings ({diag})";
                _status.Update("SalesRankings", 0, DateTime.Now, errorMsg);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError("[SalesRankings] Erro geral: {Error}\n{Stack}", ex.Message, ex.StackTrace);
            _status.Update("SalesRankings", 0, DateTime.Now, $"GERAL: {ex.Message}");
        }
    }

    /// <summary>
    /// Monta os rankings de um vendedor específico: top produtos, top clientes e vendas por região.
    /// </summary>
    private async Task<object> BuildSellerRankingsAsync(
        int sellerId, string firstDay, string lastDay, DateTime now, string period, CancellationToken ct)
    {
        // ── Top 10 Produtos ─────────────────────────────────────────────────
        var topProducts = await _firebird.QueryAsync(@"
            SELECT FIRST 10
                   DESCRICAO, ID_PRODUTO,
                   SUM(TOTAL_QTDE) AS TOTAL_QTD,
                   SUM(TOTAL_VALOR) AS TOTAL_VALOR,
                   COUNT(DISTINCT ID_PEDIDO) AS NUM_PEDIDOS
            FROM L_VENDAS_PRODUTO
            WHERE ID_VENDEDOR = @VENDEDOR
              AND DATA_HORA >= @DATA_INI
              AND DATA_HORA <= @DATA_FIM
            GROUP BY DESCRICAO, ID_PRODUTO
            ORDER BY TOTAL_VALOR DESC",
            new Dictionary<string, object?>
            {
                { "@VENDEDOR", sellerId },
                { "@DATA_INI", firstDay },
                { "@DATA_FIM", lastDay },
            }, ct);

        // ── Top 10 Clientes ─────────────────────────────────────────────────
        var topClients = await _firebird.QueryAsync(@"
            SELECT FIRST 10
                   NOME, ID_CLIENTE,
                   SUM(TOTAL_VALOR) AS TOTAL_VALOR,
                   COUNT(DISTINCT ID_PEDIDO) AS NUM_PEDIDOS
            FROM L_VENDAS_CLIENTE
            WHERE ID_VENDEDOR = @VENDEDOR
              AND DATA_HORA >= @DATA_INI
              AND DATA_HORA <= @DATA_FIM
            GROUP BY NOME, ID_CLIENTE
            ORDER BY TOTAL_VALOR DESC",
            new Dictionary<string, object?>
            {
                { "@VENDEDOR", sellerId },
                { "@DATA_INI", firstDay },
                { "@DATA_FIM", lastDay },
            }, ct);

        // ── Faturamento Diário (dentro do período) ───────────────────────
        var revenueByDay = await _firebird.QueryAsync(@"
            SELECT CAST(DATA_HORA AS DATE) AS DIA,
                   SUM(TOTAL_VALOR) AS TOTAL_VALOR,
                   COUNT(DISTINCT ID_PEDIDO) AS NUM_PEDIDOS
            FROM L_VENDAS_CLIENTE
            WHERE ID_VENDEDOR = @VENDEDOR
              AND DATA_HORA >= @DATA_INI
              AND DATA_HORA <= @DATA_FIM
            GROUP BY CAST(DATA_HORA AS DATE)
            ORDER BY DIA ASC",
            new Dictionary<string, object?> {
                { "@VENDEDOR", sellerId },
                { "@DATA_INI", firstDay },
                { "@DATA_FIM", lastDay }
            }, ct);

        // ── Heatmap (Dias da Semana — dentro do período) ─────────────────
        var heatmapStats = await _firebird.QueryAsync(@"
            SELECT EXTRACT(WEEKDAY FROM DATA_HORA) AS DOW,
                   SUM(TOTAL_VALOR) AS TOTAL_VALOR,
                   COUNT(DISTINCT ID_PEDIDO) AS NUM_PEDIDOS
            FROM L_VENDAS_CLIENTE
            WHERE ID_VENDEDOR = @VENDEDOR
              AND DATA_HORA >= @DATA_INI
              AND DATA_HORA <= @DATA_FIM
            GROUP BY EXTRACT(WEEKDAY FROM DATA_HORA)",
            new Dictionary<string, object?> {
                { "@VENDEDOR", sellerId },
                { "@DATA_INI", firstDay },
                { "@DATA_FIM", lastDay }
            }, ct);

        // ── Saúde da Carteira (Ativos, Inativos, Perdidos) ─────────────────
        var clientHealth = await _firebird.QueryAsync(@"
            SELECT
                SUM(CASE WHEN DATEDIFF(day, ULTIMA_VENDA, CURRENT_DATE) <= 30 THEN 1 ELSE 0 END) AS ATIVOS,
                SUM(CASE WHEN DATEDIFF(day, ULTIMA_VENDA, CURRENT_DATE) > 30 AND DATEDIFF(day, ULTIMA_VENDA, CURRENT_DATE) <= 90 THEN 1 ELSE 0 END) AS INATIVOS,
                SUM(CASE WHEN DATEDIFF(day, ULTIMA_VENDA, CURRENT_DATE) > 90 THEN 1 ELSE 0 END) AS PERDIDOS,
                COUNT(ID_CLIENTE) AS TOTAL
            FROM (
                SELECT ID_CLIENTE, MAX(CAST(DATA_HORA AS DATE)) AS ULTIMA_VENDA
                FROM L_VENDAS_CLIENTE
                WHERE ID_VENDEDOR = @VENDEDOR
                GROUP BY ID_CLIENTE
            )",
            new Dictionary<string, object?> { { "@VENDEDOR", sellerId } }, ct);

        // ── Mix por Categoria ───────────────────────────────────────────────
        var categoryMix = await _firebird.QueryAsync(@"
            SELECT FIRST 6
                   ID_DEPTO,
                   SUM(TOTAL_VALOR) AS TOTAL_VALOR
            FROM L_VENDAS_PRODUTO
            WHERE ID_VENDEDOR = @VENDEDOR
              AND DATA_HORA >= @DATA_INI
              AND DATA_HORA <= @DATA_FIM
            GROUP BY ID_DEPTO
            ORDER BY TOTAL_VALOR DESC",
            new Dictionary<string, object?> {
                { "@VENDEDOR", sellerId },
                { "@DATA_INI", firstDay },
                { "@DATA_FIM", lastDay }
            }, ct);

        // ── Vendas por Região ───────────────────────────────────────────────
        var byRegion = await _firebird.QueryAsync(@"
            SELECT FIRST 20
                   CIDADE, UF,
                   SUM(TOTAL_VALOR) AS TOTAL_VALOR,
                   COUNT(DISTINCT ID_PEDIDO) AS NUM_PEDIDOS
            FROM L_VENDAS_REGIAO
            WHERE ID_VENDEDOR = @VENDEDOR
              AND DATA_HORA >= @DATA_INI
              AND DATA_HORA <= @DATA_FIM
            GROUP BY CIDADE, UF
            ORDER BY TOTAL_VALOR DESC",
            new Dictionary<string, object?>
            {
                { "@VENDEDOR", sellerId },
                { "@DATA_INI", firstDay },
                { "@DATA_FIM", lastDay },
            }, ct);

        return new
        {
            sellerId,
            period,
            month    = now.Month,
            year     = now.Year,
            syncedAt = now.ToString("o"),
            topProducts = topProducts.Select(r => new
            {
                name      = r.GetValueOrDefault("DESCRICAO")?.ToString() ?? "",
                productId = ToInt(r, "ID_PRODUTO"),
                totalQty  = ToDouble(r, "TOTAL_QTD"),
                totalValue = ToDouble(r, "TOTAL_VALOR"),
                numOrders = ToInt(r, "NUM_PEDIDOS"),
            }).ToList(),
            topClients = topClients.Select(r => new
            {
                name       = r.GetValueOrDefault("NOME")?.ToString() ?? "",
                clientId   = ToInt(r, "ID_CLIENTE"),
                totalValue = ToDouble(r, "TOTAL_VALOR"),
                numOrders  = ToInt(r, "NUM_PEDIDOS"),
            }).ToList(),
            revenueByDay = revenueByDay.Select(r => new
            {
                date        = r.GetValueOrDefault("DIA")?.ToString() ?? "",
                totalAmount = ToDouble(r, "TOTAL_VALOR"),
                numOrders   = ToInt(r, "NUM_PEDIDOS"),
            }).ToList(),
            heatmapStats = heatmapStats.Select(r => new
            {
                dayOfWeek   = ToInt(r, "DOW"),
                totalAmount = ToDouble(r, "TOTAL_VALOR"),
                numOrders   = ToInt(r, "NUM_PEDIDOS"),
            }).ToList(),
            clientHealth = clientHealth.Select(r => new
            {
                actives   = ToInt(r, "ATIVOS"),
                inactives = ToInt(r, "INATIVOS"),
                lost      = ToInt(r, "PERDIDOS"),
                total     = ToInt(r, "TOTAL"),
            }).FirstOrDefault(),
            categoryMix = categoryMix.Select(r => new
            {
                name  = "Depto " + (r.GetValueOrDefault("ID_DEPTO")?.ToString() ?? "0"),
                total = ToDouble(r, "TOTAL_VALOR"),
            }).ToList(),
            byRegion = byRegion.Select(r => new
            {
                region     = r.GetValueOrDefault("CIDADE")?.ToString() ?? "",
                uf         = r.GetValueOrDefault("UF")?.ToString() ?? "",
                totalValue = ToDouble(r, "TOTAL_VALOR"),
                numOrders  = ToInt(r, "NUM_PEDIDOS"),
            }).ToList(),
        };
    }

    private static double ToDouble(Dictionary<string, object?> row, string key)
    {
        if (row.TryGetValue(key, out var v) && v != null)
        {
            return Convert.ToDouble(v);
        }
        return 0;
    }

    private static int ToInt(Dictionary<string, object?> row, string key)
    {
        if (row.TryGetValue(key, out var v) && v != null)
        {
            return Convert.ToInt32(v);
        }
        return 0;
    }
}
