using ColiseuSales.Worker.Config;
using ColiseuSales.Worker.Services;
using Microsoft.Extensions.Options;

namespace ColiseuSales.Worker.Jobs;

/// <summary>
/// SyncCatalogJob — Sincroniza dados do Firebird → VPS API.
///
/// Cadência: configurável via appsettings.json > Worker.CatalogSyncIntervalMinutes (padrão 15min).
///
/// Tabelas lidas do Firebird (PIVETA.FDB):
/// - FUNCIONARIOS WHERE MOB_ACESSO = 1           → /api/sync/sellers
/// - PRODUTOS JOIN PRODUTO_PRECOS WHERE ATIVO = 1 → /api/sync/catalog
/// - MOB_LISTACLIENTES                            → /api/sync/customers
/// - ESPECIE_PGTO                                 → /api/sync/payment-species
/// - MOB_LISTACONTAS                              → /api/sync/financials
///
/// Rule-02: totalmente async.
/// </summary>
public sealed partial class SyncCatalogJob
{
    private readonly FirebirdService        _firebird;
    private readonly VpsApiClient           _vps;
    private readonly AtendenteApiClient     _atendente;
    private readonly StatusStore            _status;
    private readonly ILogger<SyncCatalogJob> _logger;

    public SyncCatalogJob(
        FirebirdService        firebird,
        VpsApiClient           vps,
        AtendenteApiClient     atendente,
        StatusStore            status,
        ILogger<SyncCatalogJob> logger)
    {
        _firebird  = firebird;
        _vps       = vps;
        _atendente = atendente;
        _status    = status;
        _logger    = logger;
    }

    /// <summary>
    /// Executa o ciclo completo de sincronização: Firebird → VPS.
    ///
    /// @param since  Opcional — timestamp ISO 8601. Se fornecido, faz delta sync.
    ///               Se null, faz full sync de todos os dados.
    /// </summary>
    public async Task RunAsync(DateTime? since = null, CancellationToken ct = default)
    {
        var sw   = System.Diagnostics.Stopwatch.StartNew();
        var mode = since.HasValue ? $"delta desde {since:yyyy-MM-dd HH:mm}" : "full";
        _logger.LogInformation("[CatalogSync] Iniciando sync. Mode={Mode}", mode);
        _status.AppendLog($"[{DateTime.Now:HH:mm:ss}] === Iniciando ciclo de sync ({mode}) ===");

        // Acumula falhas por entidade sem interromper as demais
        var failed = new List<string>();

        await RunStep("Sellers",          () => SyncSellersAsync(ct),           failed);
        await RunStep("Catalog",          () => SyncCatalogAsync(null, ct),    failed); // sempre full sync — o store precisa do catálogo completo
        await RunStep("Customers",        () => SyncCustomersAsync(ct),         failed);
        await RunStep("PaymentSpecies",   () => SyncPaymentSpeciesAsync(ct),    failed);
        await RunStep("PaymentConditions",() => SyncPaymentConditionsAsync(ct), failed);
        await RunStep("Natureza",         () => SyncNaturezaOperacaoAsync(ct),  failed);
        await RunStep("PriceTables",      () => SyncPriceTablesAsync(ct),       failed);
        await RunStep("Financials",       () => SyncFinancialsAsync(ct),        failed);
        await RunStep("Performance",      () => SyncPerformanceAsync(ct),       failed);

        sw.Stop();

        var summary = failed.Count == 0
            ? $"✓ Ciclo completo em {sw.Elapsed.TotalSeconds:0.#}s. Todas as entidades sincronizadas."
            : $"⚠ Ciclo completo em {sw.Elapsed.TotalSeconds:0.#}s. Falhas: [{string.Join(", ", failed)}]";

        _logger.Log(failed.Count == 0 ? LogLevel.Information : LogLevel.Warning, "[CatalogSync] {Summary}", summary);
        _status.AppendLog($"[{DateTime.Now:HH:mm:ss}] === {summary} ===");
    }

    /// <summary>
    /// Executa um passo de sync e registra falhas no acumulador sem interromper o ciclo.
    /// </summary>
    private async Task RunStep(string name, Func<Task> step, List<string> failedAccumulator)
    {
        try
        {
            await step();
        }
        catch (Exception ex)
        {
            _logger.LogError("[CatalogSync/{Name}] Falha não capturada: {Error}", name, ex.Message);
            failedAccumulator.Add(name);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Vendedores — FUNCIONARIOS WHERE MOB_ACESSO = 1
    // ─────────────────────────────────────────────────────────────────────────

    private async Task SyncSellersAsync(CancellationToken ct)
    {
        _logger.LogDebug("[CatalogSync] Buscando vendedores...");
        try
        {
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
                _logger.LogWarning("[CatalogSync] Nenhum vendedor com MOB_ACESSO=1 encontrado.");
                _status.Update("Sellers", 0, DateTime.Now, "Nenhum vendedor com MOB_ACESSO=1");
                return;
            }

            var sellers = rows.Select(MapToApiObject).ToList();
            var ok      = await _vps.PushSellersAsync(sellers, ct);

            // Dual-push: também envia para o Atendente do Futuro
            await SafePushAtendente("Sellers", () => _atendente.PushSellersAsync(sellers, ct));

            _logger.LogInformation("[CatalogSync/Sellers] {Count} vendedores enviados. OK={Ok}", sellers.Count, ok);
            _status.Update("Sellers", sellers.Count, DateTime.Now, ok ? null : "Falha no push para VPS");
        }
        catch (Exception ex)
        {
            _logger.LogError("[CatalogSync/Sellers] Erro: {Error}", ex.Message);
            _status.Update("Sellers", 0, DateTime.Now, ex.Message);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Catálogo — PRODUTOS JOIN PRODUTO_PRECOS
    // Usa tabelas base (não a view MOB_PRODUTOS — tem dados corrompidos)
    // ─────────────────────────────────────────────────────────────────────────

    private async Task SyncCatalogAsync(DateTime? since, CancellationToken ct)
    {
        _logger.LogDebug("[CatalogSync] Buscando catálogo...");
        try
        {
            var sinceClause = since.HasValue ? "AND P.DATA_UP > @since" : string.Empty;

            var rows = await _firebird.QueryAsync($@"
                SELECT
                    P.ID_PRODUTO      AS code,
                    P.DESCRICAO       AS name,
                    P.DESCRICAO_ABREV AS nameShort,
                    P.ESTOQUE         AS stock,
                    P.UNIDADE         AS unit,
                    TRIM(P.MARCA)     AS brand,
                    C.DESCRICAO       AS category,
                    P.REF             AS reference,
                    P.CODIGO_BARRA    AS barCode,
                    P.DESCONTO_MAX    AS maxDiscount,
                    P.DATA_UP         AS updatedAt,
                    PP.PRECO_TABELA   AS price,
                    PP.PRECO_MINIMO   AS priceMin,
                    PP.PRECO_CUSTO    AS priceCost
                FROM PRODUTOS P
                INNER JOIN PRODUTO_PRECOS PP
                    ON PP.ID_PRODUTO = P.ID_PRODUTO
                   AND PP.ATIVO = 1
                LEFT JOIN CATEGORIAS C
                    ON C.ID_CATEGORIA = P.ID_CATEGORIA
                WHERE COALESCE(P.BLOQUEADO, 0) = 0
                  AND P.TIPO = 2
                {sinceClause}
                ORDER BY P.DESCRICAO",
                since.HasValue
                    ? new Dictionary<string, object?> { { "@since", since.Value } }
                    : null,
                ct);

            if (rows.Count == 0)
            {
                _logger.LogInformation("[CatalogSync/Catalog] Nenhum produto novo desde {Since}.", since);
                _status.Update("Catalog", 0, DateTime.Now);
                return;
            }

            var products = rows.Select(MapToApiObject).ToList();

            // Envia TODOS em um único POST — múltiplos POSTs sobrescreveriam o store Redis
            var ok = await _vps.PushCatalogAsync(products, ct);
            var success = ok ? products.Count : 0;

            // Dual-push: também envia para o Atendente do Futuro
            await SafePushAtendente("Catalog", () => _atendente.PushCatalogAsync(products, ct));

            _logger.LogInformation("[CatalogSync/Catalog] {Total} produtos. {Ok} sincronizados.",
                products.Count, success);
            _status.Update("Catalog", success, DateTime.Now, success == 0 ? "Falha no push" : null);
        }
        catch (Exception ex)
        {
            _logger.LogError("[CatalogSync/Catalog] Erro: {Error}", ex.Message);
            _status.Update("Catalog", 0, DateTime.Now, ex.Message);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Clientes — MOB_LISTACLIENTES
    // ─────────────────────────────────────────────────────────────────────────

    private async Task SyncCustomersAsync(CancellationToken ct)
    {
        _logger.LogDebug("[CatalogSync] Buscando clientes...");
        try
        {
            var rows = await _firebird.QueryAsync(@"
                SELECT
                    C.ID_CLIENTE    AS id,
                    C.NOME          AS name,
                    C.NOME_FANTASIA AS tradeName,
                    C.CPF_CNPJ      AS cnpj,
                    C.FONE_RES      AS phone,
                    C.CELULAR       AS mobile,
                    C.EMAIL         AS email,
                    C.ENDERECO_FULL AS street,
                    C.BAIRRO        AS neighborhood,
                    C.CEP           AS zipCode,
                    C.CIDADE        AS city,
                    C.UF            AS state,
                    C.LIMITE        AS creditLimit,
                    C.CLASSIFICACAO_DESC AS status,
                    C.ID_VENDEDOR   AS sellerId,
                    C.ID_TABELA     AS priceTableId
                FROM MOB_LISTACLIENTES C
                ORDER BY C.NOME", ct: ct);

            if (rows.Count == 0)
            {
                _logger.LogWarning("[CatalogSync/Customers] Sem clientes encontrados na view MOB_LISTACLIENTES.");
                _status.Update("Customers", 0, DateTime.Now, "MOB_LISTACLIENTES retornou 0 registros");
                return;
            }

            var customers = rows.Select(MapToApiObject).ToList();

            // Envia TODOS em um único POST — múltiplos POSTs sobrescreveriam o store Redis
            // 4.629 clientes × ~200 bytes ≈ 900KB, dentro do limite seguro do Redis/HTTP
            var ok = await _vps.PushCustomersAsync(customers, ct);
            var success = ok ? customers.Count : 0;

            // Dual-push: também envia para o Atendente do Futuro
            await SafePushAtendente("Customers", () => _atendente.PushCustomersAsync(customers, ct));

            _logger.LogInformation("[CatalogSync/Customers] {Total} clientes. {Ok} sincronizados.",
                customers.Count, success);
            _status.Update("Customers", success, DateTime.Now, success == 0 ? "Falha no push" : null);
        }
        catch (Exception ex)
        {
            _logger.LogError("[CatalogSync/Customers] Erro: {Error}", ex.Message);
            _status.Update("Customers", 0, DateTime.Now, ex.Message);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Formas de pagamento — ESPECIE_PGTO
    // ─────────────────────────────────────────────────────────────────────────

    private async Task SyncPaymentSpeciesAsync(CancellationToken ct)
    {
        try
        {
            // Filtra apenas espécies com MOB_ACESSO = 1 (Permite Acesso pelo App)
            var rows = await _firebird.QueryAsync(@"
                SELECT E.ID_ESPECIE AS id,
                       TRIM(E.DESCRICAO) AS name,
                       E.TIPO AS type,
                       E.DIAS AS days
                FROM ESPECIE_PGTO E
                WHERE E.MOB_ACESSO = 1
                ORDER BY E.DESCRICAO", ct: ct);

            var species = rows.Select(MapToApiObject).ToList();
            var ok = await _vps.PushPaymentSpeciesAsync(species, ct);

            // Dual-push: também envia para o Atendente do Futuro
            await SafePushAtendente("PaymentSpecies", () => _atendente.PushPaymentSpeciesAsync(species, ct));

            _logger.LogInformation("[CatalogSync/PaymentSpecies] {Count} espécies enviadas.", species.Count);
            _status.Update("PaymentSpecies", species.Count, DateTime.Now, ok ? null : "Falha no push");
        }
        catch (Exception ex)
        {
            _logger.LogError("[CatalogSync/PaymentSpecies] Erro: {Error}", ex.Message);
            _status.Update("PaymentSpecies", 0, DateTime.Now, ex.Message);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Condições de pagamento — FORMA_PGTO
    // ─────────────────────────────────────────────────────────────────────────

    private async Task SyncPaymentConditionsAsync(CancellationToken ct)
    {
        try
        {
            // Filtra apenas condições com MOB_ACESSO = 1, e que possuam permissão vincular na tabela FORMA_PGTO_PERMISSAO
            // Como o ERP Firebird usa N:N (uma mesma FORMA pode estar em várias ESPÉCIES via FORMA_PGTO_PERMISSAO),
            // e o App Mobile usa 1:N (uma payment_condition tem um especie_id e id único no SQLite),
            // precisamos gerar combinações únicas. Vamos enviar o ID composto: ID_FORMA_ID_ESPECIE.
            var rows = await _firebird.QueryAsync(@"
                SELECT DISTINCT 
                       (F.ID_FORMA || '_' || FP.ID_ESPECIE) AS id,
                       TRIM(F.DESCRICAO) AS descricao,
                       FP.ID_ESPECIE AS especieId,
                       F.DESCONTO_MAX AS descontoMax,
                       F.PARCELAS AS parcelas,
                       F.DIAS_ENTRADA AS diasEntrada,
                       F.DIAS_PARCELAS AS diasParcelas
                FROM FORMA_PGTO F
                INNER JOIN FORMA_PGTO_PERMISSAO FP ON FP.ID_FORMA = F.ID_FORMA
                INNER JOIN ESPECIE_PGTO E ON E.ID_ESPECIE = FP.ID_ESPECIE
                WHERE F.MOB_ACESSO = 1 AND E.MOB_ACESSO = 1
                ORDER BY F.DESCRICAO", ct: ct);

            var conditions = rows.Select(MapToApiObject).ToList();
            var ok = await _vps.PushPaymentConditionsAsync(conditions, ct);

            // Dual-push: também envia para o Atendente do Futuro
            await SafePushAtendente("PaymentConditions", () => _atendente.PushPaymentConditionsAsync(conditions, ct));

            _logger.LogInformation("[CatalogSync/PaymentConditions] {Count} condições enviadas.", conditions.Count);
            _status.Update("PaymentConditions", conditions.Count, DateTime.Now, ok ? null : "Falha no push");
        }
        catch (Exception ex)
        {
            _logger.LogError("[CatalogSync/PaymentConditions] Erro: {Error}", ex.Message);
            _status.Update("PaymentConditions", 0, DateTime.Now, ex.Message);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Tabelas de preço — TABELA_PRECOS + MOB_TABELAPRECO
    // ─────────────────────────────────────────────────────────────────────────

    /// <summary>
    /// Sincroniza tabelas de preço do Firebird para a VPS.
    ///
    /// Dois payloads:
    ///   1. /api/sync/price-tables  — cabeçalhos (ID, nome, markup%)
    ///   2. /api/sync/product-prices — preços produto×tabela via MOB_TABELAPRECO
    /// </summary>
    private async Task SyncPriceTablesAsync(CancellationToken ct)
    {
        try
        {
            // 1. Cabeçalhos das tabelas
            var tableRows = await _firebird.QueryAsync(@"
                SELECT
                    T.ID_TABELA        AS id,
                    TRIM(T.DESCRICAO)  AS name,
                    T.PRECOT_P         AS markupPct
                FROM TABELA_PRECOS T
                ORDER BY T.DESCRICAO", ct: ct);

            var tables = tableRows.Select(MapToApiObject).ToList();

            if (tables.Count == 0)
            {
                _logger.LogInformation("[CatalogSync/PriceTables] Nenhuma tabela de preço cadastrada no ERP.");
                _status.Update("PriceTables", 0, DateTime.Now);
                return;
            }

            var okTables = await _vps.PushPriceTablesAsync(tables, ct);
            await SafePushAtendente("PriceTables", () => _atendente.PushPriceTablesAsync(tables, ct));

            // 2. Preços produto × tabela
            // Usamos query direta equivalente à MOB_TABELAPRECO para evitar o
            // "Dynamic SQL Error" causado pelo EXECUTE STATEMENT 'SET GENERATOR GEN_SEQ TO 0'
            // dentro da procedure (o generator GEN_SEQ pode não existir no banco).
            // Lógica idêntica: PRECO_TABELA + (PRECO_TABELA * PRECOT_P / 100)
            var priceRows = await _firebird.QueryAsync(@"
                SELECT
                    CAST(PR.ID_PRODUTO AS VARCHAR(20))                                  AS productCode,
                    CAST(T.ID_TABELA   AS VARCHAR(20))                                  AS priceTableId,
                    COALESCE(TPI.PRECO_TABELA, PP.PRECO_TABELA + ((PP.PRECO_TABELA * T.PRECOT_P) / 100.0)) AS price
                FROM PRODUTOS PR
                INNER JOIN PRODUTO_PRECOS PP ON PP.ID_PRODUTO = PR.ID_PRODUTO
                CROSS JOIN TABELA_PRECOS T
                LEFT JOIN TABELA_PRECOS_ITENS TPI ON TPI.ID_PRODUTO = PR.ID_PRODUTO AND TPI.ID_TABELA = T.ID_TABELA
                WHERE PP.ATIVO = 1
                  AND PR.TIPO <> 4
                ORDER BY PR.ID_PRODUTO, T.ID_TABELA", ct: ct);

            var prices = priceRows.Select(MapToApiObject).ToList();
            var okPrices = await _vps.PushProductPricesAsync(prices, ct);
            await SafePushAtendente("ProductPrices", () => _atendente.PushProductPricesAsync(prices, ct));

            _logger.LogInformation(
                "[CatalogSync/PriceTables] {TableCount} tabelas e {PriceCount} preços enviados. OK={OkT}/{OkP}",
                tables.Count, prices.Count, okTables, okPrices);
            _status.Update("PriceTables", tables.Count, DateTime.Now,
                (okTables && okPrices) ? null : "Falha parcial no push");
        }
        catch (Exception ex)
        {
            _logger.LogError("[CatalogSync/PriceTables] Erro: {Error}", ex.Message);
            _status.Update("PriceTables", 0, DateTime.Now, ex.Message);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Naturezas de operação — NATUREZA_OPERACAO WHERE MOB_ACESSO='S'
    // ─────────────────────────────────────────────────────────────────────────

    private async Task SyncNaturezaOperacaoAsync(CancellationToken ct)
    {
        try
        {
            // Filtra somente naturezas com MOB_ACESSO = 1, ordenadas por MOB_ORDEM
            var rows = await _firebird.QueryAsync(@"
                SELECT N.ID_NATUREZA       AS id,
                       TRIM(N.DESCRICAO)   AS descricao,
                       TRIM(N.DESCRICAO_NOTA) AS descricaoNota,
                       N.CODIGO_FISCAL     AS codigoFiscal,
                       N.ES                AS es,
                       N.MOB_ORDEM         AS mobOrdem
                FROM NATUREZA_OPERACAO N
                WHERE N.MOB_ACESSO = 1
                ORDER BY N.MOB_ORDEM ASC, N.DESCRICAO ASC", ct: ct);

            var naturezas = rows.Select(MapToApiObject).ToList();
            var ok = await _vps.PushNaturezaAsync(naturezas, ct);

            // Dual-push: também envia para o Atendente do Futuro
            await SafePushAtendente("Natureza", () => _atendente.PushNaturezaAsync(naturezas, ct));

            _logger.LogInformation("[CatalogSync/Natureza] {Count} naturezas enviadas.", naturezas.Count);
            _status.Update("Natureza", naturezas.Count, DateTime.Now, ok ? null : "Falha no push");
        }
        catch (Exception ex)
        {
            _logger.LogError("[CatalogSync/Natureza] Erro: {Error}", ex.Message);
            _status.Update("Natureza", 0, DateTime.Now, ex.Message);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Financeiro — MOB_LISTACONTAS
    // ─────────────────────────────────────────────────────────────────────────

    private async Task SyncFinancialsAsync(CancellationToken ct)
    {
        try
        {
            var rows = await _firebird.QueryAsync(@"
                SELECT
                    T.ID_CONTA             AS id,
                    T.ID_CLIENTE           AS customer_id,
                    T.N_DOC                AS doc_number,
                    T.VALOR_CALC           AS amount,
                    T.JUROS_CALC           AS interest,
                    T.DATA_VENCIMENTO_FMT  AS due_date,
                    T.ID_ESPECIE           AS payment_species_id,
                    T.BAIXA                AS is_paid,
                    T.TIPO                 AS type,
                    T.STATUS_TEXTO         AS payment_date
                FROM MOB_LISTACONTAS T
                ORDER BY T.DATA_VENCIMENTO_FMT DESC
                ROWS 2000", ct: ct);

            var financials = rows.Select(MapToApiObject).ToList();
            var ok = await _vps.PushFinancialsAsync(financials, ct);

            // Dual-push: também envia para o Atendente do Futuro
            await SafePushAtendente("Financials", () => _atendente.PushFinancialsAsync(financials, ct));

            _logger.LogInformation("[CatalogSync/Financials] {Count} títulos enviados.", financials.Count);
            _status.Update("Financials", financials.Count, DateTime.Now, ok ? null : "Falha no push");
        }
        catch (Exception ex)
        {
            _logger.LogError("[CatalogSync/Financials] Erro: {Error}", ex.Message);
            _status.Update("Financials", 0, DateTime.Now, ex.Message);
        }
    }

    /// <summary>
    /// Sincroniza KPIs de desempenho do vendedor (MINHASVENDAS + MINHASVENDASR).
    ///
    /// Para cada vendedor com MOB_ACESSO=1, executa as duas procedures e
    /// envia os resultados consolidados para a VPS. O middleware armazena
    /// no dataStore para servir ao mobile sem conexão direta com Firebird.
    /// </summary>
    private async Task SyncPerformanceAsync(CancellationToken ct)
    {
        _logger.LogDebug("[CatalogSync] Buscando KPIs de desempenho...");
        try
        {
            // Busca vendedores ativos
            var sellers = await _firebird.QueryAsync(
                "SELECT ID_FUNCIONARIO FROM FUNCIONARIOS WHERE MOB_ACESSO = 1",
                ct: ct);

            if (sellers.Count == 0)
            {
                _status.Update("Performance", 0, DateTime.Now, "Nenhum vendedor ativo");
                return;
            }

            var now = DateTime.Now;
            var month = now.Month;
            var year = now.Year;
            var today = now.ToString("yyyy-MM-dd");
            var firstDay = $"{year}-{month:D2}-01";
            var lastDay = new DateTime(year, month, DateTime.DaysInMonth(year, month)).ToString("yyyy-MM-dd");

            var kpiList = new List<object>();

            foreach (var seller in sellers)
            {
                var sellerId = Convert.ToInt32(seller["ID_FUNCIONARIO"]);
                try
                {
                    // MINHASVENDAS(VENDEDOR, MES, ANO, DATA)
                    var mainResult = await _firebird.ExecuteProcedureAsync(
                        "MINHASVENDAS",
                        new Dictionary<string, object?>
                        {
                            { "@VENDEDOR", sellerId },
                            { "@MES", month },
                            { "@ANO", year },
                            { "@DATA", today },
                        }, ct);

                    // MINHASVENDASR(VENDEDOR, DATAI, DATAF, DIA, EMPRESA)
                    var rangeResult = await _firebird.ExecuteProcedureAsync(
                        "MINHASVENDASR",
                        new Dictionary<string, object?>
                        {
                            { "@VENDEDOR", sellerId },
                            { "@DATAI", firstDay },
                            { "@DATAF", lastDay },
                            { "@DIA", today },
                            { "@EMPRESA", 1 },
                        }, ct);

                    var main = mainResult.FirstOrDefault() ?? new();
                    var range = rangeResult.FirstOrDefault() ?? new();

                    kpiList.Add(new
                    {
                        sellerId,
                        month,
                        year,
                        syncedAt = now.ToString("o"),
                        vendaDiaria = ToDouble(main, "VENDA_DIARIA"),
                        vendaMensal = ToDouble(main, "VENDA_MENSAL"),
                        comissaoDiaria = ToDouble(main, "COMISSAO_DIARIA"),
                        comissaoMensal = ToDouble(main, "COMISSAO_MENSAL"),
                        metaDiaria = ToDouble(main, "META_DIARIA"),
                        metaMensal = ToDouble(main, "META_MENSAL"),
                        servicoMensal = ToDouble(main, "SERVICO_MENSAL"),
                        comissaoSvMensal = ToDouble(main, "COMISSAO_SV_MENSAL"),
                        totalDiario = ToDouble(range, "TOTAL_DIARIO"),
                        totalMensal = ToDouble(range, "TOTAL_MENSAL"),
                        comissaoDiariaR = ToDouble(range, "COMISSAO_DIARIA"),
                        comissaoMensalR = ToDouble(range, "COMISSAO_MENSAL"),
                    });
                }
                catch (Exception ex)
                {
                    _logger.LogWarning("[CatalogSync/Performance] Erro seller {Id}: {Error}", sellerId, ex.Message);
                }
            }

            if (kpiList.Count > 0)
            {
                var ok = await _vps.PushPerformanceAsync(kpiList, ct);
                _logger.LogInformation("[CatalogSync/Performance] {Count} vendedores sincronizados. OK={Ok}", kpiList.Count, ok);
                _status.Update("Performance", kpiList.Count, DateTime.Now, ok ? null : "Falha no push");
            }
            else
            {
                _status.Update("Performance", 0, DateTime.Now, "Nenhum KPI obtido");
            }
        }
        catch (Exception ex)
        {
            _logger.LogError("[CatalogSync/Performance] Erro: {Error}", ex.Message);
            _status.Update("Performance", 0, DateTime.Now, ex.Message);
        }
    }

    /// <summary>Extrai double de um dicionário Firebird com segurança.</summary>
    private static double ToDouble(Dictionary<string, object?> row, string key)
        => row.TryGetValue(key, out var val) && val != null ? Convert.ToDouble(val) : 0;

    // ─────────────────────────────────────────────────────────────────────────
    // Helper: converte row do Firebird para objeto anônimo da API
    // ─────────────────────────────────────────────────────────────────────────

    // Campos do Firebird que são bool no DTO mas vêm como char 'S'/'N' ou int 0/1
    private static readonly HashSet<string> _boolFields = new(StringComparer.OrdinalIgnoreCase)
    {
        "isPaid", "baixa", "ativo", "isActive", "mobAcesso"
    };

    private static object MapToApiObject(Dictionary<string, object?> row)
    {
        var result = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
        foreach (var (key, value) in row)
        {
            var camel = ToCamelCase(key);
            object? v = value is string s ? s.Trim() : value;
            if (v == DBNull.Value || v is DBNull) v = null;

            if (v is not null)
            {
                // id/code e campos de referência: Firebird retorna int, DTOs esperam string
                if ((camel == "code" || camel == "id" || camel == "type"
                        || camel.EndsWith("Id",  StringComparison.OrdinalIgnoreCase)
                        || camel.EndsWith("Code", StringComparison.OrdinalIgnoreCase))
                    && v is not string)
                    v = v.ToString();

                // DateTime → string ISO 8601 (DTOs usam string? para datas)
                if (v is DateTime dt)
                    v = dt.ToString("O");
                else if (v is DateTimeOffset dto2)
                    v = dto2.ToString("O");

                // Bool-char: Firebird armazena 'S'/'N' ou '1'/'0' para booleans
                else if (_boolFields.Contains(camel))
                {
                    v = v switch
                    {
                        bool b   => b,
                        string sc => sc.Equals("S", StringComparison.OrdinalIgnoreCase) || sc == "1",
                        int    iv => iv != 0,
                        long   lv => lv != 0,
                        _         => v
                    };
                }
            }

            result[camel] = v;
        }
        return result;
    }


    /// <summary>
    /// Converte nome de coluna SQL (UPPER_SNAKE_CASE) para camelCase.
    ///
    /// Exemplos:
    ///   ID_PRODUTO    → idProduto
    ///   DATA_UP       → dataUp
    ///   PRECO_MINIMO  → precoMinimo
    ///   ID            → id
    ///   isPaid        → isPaid (passthrough se já camelCase)
    /// </summary>
    [System.Text.RegularExpressions.GeneratedRegex(@"_([a-zA-Z])")]
    private static partial System.Text.RegularExpressions.Regex UnderscoreLetterRegex();

    private static string ToCamelCase(string s)
    {
        if (string.IsNullOrEmpty(s)) return s;
        // Converte para lowercase e capitaliza letra após underscore
        var lower  = s.ToLowerInvariant();
        var camel  = UnderscoreLetterRegex().Replace(lower, m => m.Groups[1].Value.ToUpperInvariant());
        return camel;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Dual-push helper — erros do Atendente NUNCA afetam o sync do Coliseu
    // ─────────────────────────────────────────────────────────────────────────

    /// <summary>
    /// Executa push para o Atendente do Futuro com isolamento total de erros.
    /// Se o Atendente falhar, apenas loga um warning — o sync do Coliseu Sales não é afetado.
    /// </summary>
    private async Task SafePushAtendente(string entity, Func<Task> pushAction)
    {
        if (!_atendente.IsEnabled) return;

        try
        {
            await pushAction();
            _logger.LogDebug("[CatalogSync/Atendente] {Entity} sincronizado com sucesso.", entity);
        }
        catch (Exception ex)
        {
            // Falha no Atendente não deve afetar o Coliseu Sales
            _logger.LogWarning(
                "[CatalogSync/Atendente] Falha ao sincronizar {Entity}: {Error}",
                entity, ex.Message);
        }
    }
}
