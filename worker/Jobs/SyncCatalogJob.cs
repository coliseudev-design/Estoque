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
    private readonly IdentityApiClient      _identity;
    private readonly string                 _companyId;
    private readonly ChangeTrackerService   _changeTracker;

    private List<BranchDto>? _cachedBranches;

    public SyncCatalogJob(
        FirebirdService        firebird,
        VpsApiClient           vps,
        AtendenteApiClient     atendente,
        StatusStore            status,
        IOptions<VpsApiOptions> vpsOpts,
        IdentityApiClient      identity,
        ILogger<SyncCatalogJob> logger,
        ChangeTrackerService changeTracker)
    {
        _firebird  = firebird;
        _vps       = vps;
        _atendente = atendente;
        _status    = status;
        _logger    = logger;
        _identity  = identity;
        _companyId = vpsOpts.Value.CompanyId;
        _changeTracker = changeTracker;
    }

    /// <summary>
    /// Executa o ciclo completo de sincronização: Firebird → VPS.
    ///
    /// @param since  Opcional — timestamp ISO 8601. Se fornecido, faz delta sync.
    ///               Se null, faz full sync de todos os dados.
    /// </summary>
    public async Task RunAsync(bool force = false, DateTime? since = null, CancellationToken ct = default)
    {
        var tables = new[] { "PRODUTOS", "CLIENTES", "FUNCIONARIOS", "EMPRESA", "ESPECIE_PGTO", "FORMA_PGTO", "NATUREZA_OPERACAO", "TABELA_PRECO", "CONTAS", "PEDIDOS" };

        if (!force && !await _changeTracker.HasChangesAsync("CatalogSync", tables))
        {
            _logger.LogDebug("[CatalogSync] Sem alterações pendentes no Firebird. Ignorando este ciclo.");
            return;
        }

        var sw   = System.Diagnostics.Stopwatch.StartNew();
        var mode = since.HasValue ? $"delta desde {since:yyyy-MM-dd HH:mm}" : "full";
        _logger.LogInformation("[CatalogSync] Iniciando sync. Mode={Mode}", mode);
        _status.AppendLog($"[{DateTime.Now:HH:mm:ss}] === Iniciando ciclo de sync ({mode}) ===");

        var failed = new List<string>();

        if (Guid.TryParse(_companyId, out var cid))
        {
            _cachedBranches = await _identity.GetBranchesAsync(cid, ct);
        }

        await RunStep("CompanyData",      () => SyncCompanyDataAsync(ct),       failed);
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

        await _changeTracker.UpdateLastProcessedLogIdAsync("CatalogSync", tables);
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
    // Dados da Empresa — EMPRESA
    // ─────────────────────────────────────────────────────────────────────────

    private async Task SyncCompanyDataAsync(CancellationToken ct)
    {
        _logger.LogDebug("[CatalogSync] Buscando dados da empresa...");
        try
        {
            var rows = await _firebird.QueryAsync(@"
                SELECT
                    ID_EMPRESA      AS id,
                    NOME_EMPRESA    AS name,
                    RAZAO_SOCIAL    AS tradeName,
                    CNPJ            AS cnpj,
                    EMAIL           AS email,
                    FONE1           AS phone,
                    ENDERECO        AS street,
                    BAIRRO          AS neighborhood,
                    CEP             AS zipCode
                FROM EMPRESA
                ORDER BY ID_EMPRESA", ct: ct);

            if (rows.Count == 0)
            {
                _logger.LogWarning("[CatalogSync/CompanyData] Tabela EMPRESA vazia.");
                _status.Update("CompanyData", 0, DateTime.Now, "Nenhum registro encontrado");
                return;
            }

            var company = rows.Select(MapToApiObject).ToList();
            var ok = await _vps.PushCompanyDataAsync(company, ct);



            _logger.LogInformation("[CatalogSync/CompanyData] {Count} empresas sincronizadas.", company.Count);
            _status.Update("CompanyData", company.Count, DateTime.Now, ok ? null : "Falha no push");
        }
        catch (Exception ex)
        {
            _logger.LogError("[CatalogSync/CompanyData] Erro: {Error}", ex.Message);
            _status.Update("CompanyData", 0, DateTime.Now, ex.Message);
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
            var branchFilter = "";
            if (_cachedBranches != null && _cachedBranches.Count > 0)
            {
                var empresaIds = string.Join(",", _cachedBranches.Select(b => b.ErpEmpresaId));
                branchFilter = $" AND (F.ID_EMPRESA IN ({empresaIds}) OR F.ID_EMPRESA IS NULL)";
            }

            var rows = await _firebird.QueryAsync($@"
                SELECT
                    F.ID_FUNCIONARIO  AS id,
                    F.ID_MOBILE       AS mobileId,
                    F.NOME            AS name,
                    F.EMAIL           AS email,
                    F.MOB_SENHA       AS passwordHash,
                    F.DESCONTO_MAX    AS maxDiscount,
                    F.COMISSAO        AS commissionRate,
                    F.ID_EMPRESA      AS erpEmpresaId
                FROM FUNCIONARIOS F
                WHERE F.MOB_ACESSO = 1 {branchFilter}
                ORDER BY F.NOME", ct: ct);

            if (rows.Count == 0)
            {
                _logger.LogWarning("[CatalogSync] Nenhum vendedor com MOB_ACESSO=1 encontrado.");
                _status.Update("Sellers", 0, DateTime.Now, "Nenhum vendedor com MOB_ACESSO=1");
                return;
            }

            var sellers = rows.Select(MapToApiObject).ToList();
            // [FIX] Passa branchId da filial padrão para isolar no Redis por filial
            var defaultBranchId = _cachedBranches?.FirstOrDefault(b => b.IsDefault)?.Id
                               ?? _cachedBranches?.FirstOrDefault()?.Id;
            var ok      = await _vps.PushSellersAsync(sellers, defaultBranchId, ct);

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

            var branchesToSync = _cachedBranches != null && _cachedBranches.Count > 0 
                ? _cachedBranches 
                : new List<BranchDto> { new BranchDto(Guid.Empty, "Default", null, 1, 1, 1, true) };

            int totalSuccess = 0;
            bool isFirst = true;

            foreach (var branch in branchesToSync)
            {
                if (branch.ErpDeptoPadrao <= 0)
                {
                    _logger.LogWarning("[CatalogSync/Catalog] Filial {BranchName} ignorada no catálogo por possuir ErpDeptoPadrao inválido ({Depto}).", branch.Name, branch.ErpDeptoPadrao);
                    continue;
                }

                _logger.LogInformation("[CatalogSync/Catalog] Sincronizando catálogo para a filial {BranchName} (Depto: {Depto})...", branch.Name, branch.ErpDeptoPadrao);

                var queryParams = new Dictionary<string, object?>
                {
                    { "@erpDeptoPadrao", branch.ErpDeptoPadrao }
                };
                if (since.HasValue)
                {
                    queryParams.Add("@since", since.Value);
                }

                var rows = await _firebird.QueryAsync($@"
                    SELECT
                        P.ID_PRODUTO      AS code,
                        P.DESCRICAO       AS name,
                        P.DESCRICAO_ABREV AS nameShort,
                        COALESCE(PD.ESTOQUE, 0) AS stock,
                        P.UNIDADE         AS unit,
                        L.NOME            AS brand,
                        C.DESCRICAO       AS category,
                        P.REF             AS reference,
                        P.CODIGO_FAB      AS factoryCode,
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
                    LEFT JOIN PRODUTO_DEPTOS PD
                        ON PD.ID_PRODUTO = P.ID_PRODUTO
                       AND PD.ID_DEPTO = @erpDeptoPadrao
                    LEFT JOIN CATEGORIAS C
                        ON C.ID_CATEGORIA = P.ID_CATEGORIA
                    LEFT JOIN LABORATORIOS L
                        ON L.ID_LABORATORIO = P.ID_MARCA
                    WHERE COALESCE(P.BLOQUEADO, 0) = 0
                      AND P.TIPO = 2
                    {sinceClause}
                    ORDER BY P.DESCRICAO",
                    queryParams,
                    ct);

                if (rows.Count == 0)
                {
                    _logger.LogInformation("[CatalogSync/Catalog] Nenhum produto para a filial {BranchName}.", branch.Name);
                    continue;
                }

                var products = rows.Select(r =>
                {
                    var obj = (Dictionary<string, object?>)MapToApiObject(r);
                    obj["erpDeptoPadrao"] = branch.ErpDeptoPadrao;
                    return (object)obj;
                }).ToList();

                var catalogBranchId = branch.Id != Guid.Empty ? (Guid?)branch.Id : null;
                var ok = await _vps.PushCatalogAsync(products, catalogBranchId, ct);
                
                if (ok)
                {
                    totalSuccess += products.Count;
                }

                // Dual-push: Envia para o Atendente apenas uma vez (na primeira filial) para evitar duplicar custo na API do Atendente
                if (isFirst)
                {
                    await SafePushAtendente("Catalog", () => _atendente.PushCatalogAsync(products, ct));
                    isFirst = false;
                }
            }

            _logger.LogInformation("[CatalogSync/Catalog] {Total} total de produtos sincronizados em todas as filiais.", totalSuccess);
            _status.Update("Catalog", totalSuccess, DateTime.Now, totalSuccess == 0 ? "Falha no push ou sem registros" : null);
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
                    CAST(C.NOME AS VARCHAR(70)) AS name,
                    CAST(C.NOME_FANTASIA AS VARCHAR(50)) AS tradeName,
                    C.CPF_CNPJ      AS cnpj,
                    CD.FONE_RES     AS phone,
                    CD.CELULAR      AS mobile,
                    C.EMAIL         AS email,
                    (CD.ENDERECO || ', ' || CD.NUMERO) AS street,
                    CD.BAIRRO       AS neighborhood,
                    CD.CEP          AS zipCode,
                    R.CIDADE        AS city,
                    R.UF            AS state,
                    C.LIMITE        AS creditLimit,
                    CASE when (C.classificacao = 0) then 'NAO DEFINIDO'
                         when (C.classificacao = 1) then 'INATIVO'
                         when (C.classificacao = 2) then 'RUIM'
                         when (C.classificacao = 3) then 'REGULAR'
                         when (C.classificacao = 4) then 'BOM'
                         when (C.classificacao = 5) then 'OTIMO'
                         when (C.classificacao = 6) then 'PREFERENCIAL'
                         when (C.classificacao = 96) then 'PENDENTE'
                         when (C.classificacao = 97) then 'EM COBRANCA'
                         when (C.classificacao = 98) then 'INADIMPLENTE'
                         when (C.classificacao = 99) then 'NEGATIVO'
                         END        AS status,
                    C.ID_VENDEDOR   AS sellerId,
                    C.ID_TABELA     AS priceTableId
                FROM CLIENTES C
                LEFT JOIN CLIENTES_DADOS CD ON CD.ID_CLIENTE = C.ID_CLIENTE
                LEFT JOIN REGIOES R ON R.ID_REGIAO = C.ID_REGIAO
                WHERE C.CLASSIFICACAO <> 1 AND C.TIPO = 1
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
            // [FIX] Passa branchId da filial padrão para isolar clientes por filial no Redis
            var customerBranchId = _cachedBranches?.FirstOrDefault(b => b.IsDefault)?.Id
                                ?? _cachedBranches?.FirstOrDefault()?.Id;
            var ok = await _vps.PushCustomersAsync(customers, customerBranchId, ct);
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
            // [FIX] Formas de pagamento são compartilhadas entre filiais: sem branchId
            var ok = await _vps.PushPaymentSpeciesAsync(species, null, ct);

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
            // [FIX] Condições de pagamento são compartilhadas: sem branchId
            var ok = await _vps.PushPaymentConditionsAsync(conditions, null, ct);

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

            var okTables = await _vps.PushPriceTablesAsync(tables, null, ct);
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
            var okPrices = await _vps.PushProductPricesAsync(prices, null, ct);
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
                       N.PROCESSO          AS processo,
                       N.TIPO              AS tipo,
                       N.MOB_ORDEM         AS mobOrdem
                FROM NATUREZA_OPERACAO N
                WHERE N.MOB_ACESSO = 1
                ORDER BY N.MOB_ORDEM ASC, N.DESCRICAO ASC", ct: ct);

            var naturezas = rows.Select(MapToApiObject).ToList();
            // [FIX] Naturezas são compartilhadas entre filiais: sem branchId
            var ok = await _vps.PushNaturezaAsync(naturezas, null, ct);

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
            var branchesToSync = _cachedBranches != null && _cachedBranches.Count > 0 
                ? _cachedBranches 
                : new List<BranchDto> { new BranchDto(Guid.Empty, "Default", null, 1, 1, 1, true) };

            int totalSuccess = 0;
            bool isFirst = true;

            foreach (var branch in branchesToSync)
            {
                if (branch.Id != Guid.Empty && branch.ErpDeptoPadrao <= 0)
                {
                    _logger.LogWarning("[CatalogSync/Financials] Filial {BranchName} ignorada no financeiro por possuir ErpDeptoPadrao inválido ({Depto}).", branch.Name, branch.ErpDeptoPadrao);
                    continue;
                }

                _logger.LogInformation("[CatalogSync/Financials] Sincronizando títulos para a filial {BranchName} (Depto: {Depto})...", branch.Name, branch.ErpDeptoPadrao);

                var queryParams = new Dictionary<string, object?>();
                var deptoFilter = "";

                if (branch.Id != Guid.Empty)
                {
                    deptoFilter = "AND C.ID_DEPTO = @erpDeptoPadrao";
                    queryParams.Add("@erpDeptoPadrao", branch.ErpDeptoPadrao);
                }

                var rows = await _firebird.QueryAsync($@"
                    SELECT
                        C.ID_CONTA             AS id,
                        C.ID_CLIENTE           AS customer_id,
                        C.N_DOC                AS doc_number,
                        (CASE WHEN C.TIPO = 3 THEN (C.VALOR * -1) ELSE C.VALOR END) AS amount,
                        ((CASE WHEN ((CURRENT_DATE - C.DATA_VENCIMENTO) > 0) AND ((CURRENT_DATE - C.DATA_VENCIMENTO) < 10000) THEN (C.VALOR * CAST(( dpower( CAST((1+(C.JUROS_DEPOIS/100.0)) AS FLOAT), CAST((CAST((CURRENT_DATE - C.DATA_VENCIMENTO) AS FLOAT)/30.0) AS FLOAT) )) AS FLOAT)) ELSE C.VALOR END) - C.VALOR) AS interest,
                        (LPAD(EXTRACT(YEAR FROM C.DATA_VENCIMENTO), 4, '0') || '-' || LPAD(EXTRACT(MONTH FROM C.DATA_VENCIMENTO), 2, '0') || '-' || LPAD(EXTRACT(DAY FROM C.DATA_VENCIMENTO), 2, '0')) AS due_date,
                        C.ID_ESPECIE           AS payment_species_id,
                        C.BAIXA                AS is_paid,
                        C.TIPO                 AS type,
                        CASE WHEN (C.BAIXA = 0) THEN 'EM ABERTO'
                             WHEN (C.BAIXA = 0) AND (C.DATA_VENCIMENTO < CURRENT_DATE) THEN 'VENCIDA'
                             WHEN (C.BAIXA = 1) THEN 'QUITADA'
                             WHEN (C.BAIXA = 2) THEN 'PARCIAL'
                             WHEN (C.BAIXA = 8) THEN 'RENEGOCIADA'
                             WHEN (C.BAIXA = 9) THEN 'CANCELADA'
                             END               AS payment_date
                    FROM CONTAS C
                    WHERE C.BAIXA = 0
                      {deptoFilter}
                    ORDER BY C.DATA_VENCIMENTO DESC",
                    queryParams,
                    ct);

                if (rows.Count == 0)
                {
                    _logger.LogInformation("[CatalogSync/Financials] Nenhum título em aberto para a filial {BranchName}.", branch.Name);
                    continue;
                }

                var financials = rows.Select(MapToApiObject).ToList();
                var finBranchId = branch.Id != Guid.Empty ? (Guid?)branch.Id : null;
                
                var ok = await _vps.PushFinancialsAsync(financials, finBranchId, ct);
                
                if (ok)
                {
                    totalSuccess += financials.Count;
                }

                // Dual-push: Envia para o Atendente apenas uma vez
                if (isFirst)
                {
                    await SafePushAtendente("Financials", async () =>
                    {
                        await _atendente.PushFinancialsAsync(financials, ct);
                    });
                    isFirst = false;
                }
            }

            _logger.LogInformation("[CatalogSync/Financials] {Total} total de títulos enviados.", totalSuccess);
            _status.Update("Financials", totalSuccess, DateTime.Now, totalSuccess == 0 ? "Falha no push ou sem registros" : null);
        }
        catch (Exception ex)
        {
            _logger.LogError("[CatalogSync/Financials] Erro: {Error}", ex.Message);
            _status.Update("Financials", 0, DateTime.Now, ex.Message);
        }
    }

    /// <summary>
    /// Sincroniza KPIs de desempenho do vendedor (Isolated by branch).
    ///
    /// Para cada vendedor com MOB_ACESSO=1 e cada filial, executa blocos SQL
    /// que simulam as procedures MINHASVENDAS e MINHASVENDASR com filtro ID_DEPTO.
    /// envia os resultados consolidados para a VPS.
    /// </summary>
    private async Task SyncPerformanceAsync(CancellationToken ct)
    {
        _logger.LogDebug("[CatalogSync] Buscando KPIs de desempenho...");
        try
        {
            var branchFilter = "";
            if (_cachedBranches != null && _cachedBranches.Count > 0)
            {
                var empresaIds = string.Join(",", _cachedBranches.Select(b => b.ErpEmpresaId));
                branchFilter = $" AND (ID_EMPRESA IN ({empresaIds}) OR ID_EMPRESA IS NULL)";
            }

            var sellers = await _firebird.QueryAsync(
                $"SELECT ID_FUNCIONARIO, COALESCE(ID_EMPRESA, 1) AS ID_EMPRESA FROM FUNCIONARIOS WHERE MOB_ACESSO = 1 {branchFilter}",
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



            var mobMinhasVendasSql = @"
EXECUTE BLOCK (
    VENDEDOR INTEGER = @VENDEDOR,
    MES INTEGER = @MES,
    ANO INTEGER = @ANO,
    DATA DATE = @DATA,
    EMPRESA INTEGER = @EMPRESA
)
RETURNS (
    VENDA_DIARIA NUMERIC(15,2), VENDA_MENSAL NUMERIC(15,2),
    COMISSAO_DIARIA NUMERIC(15,2), COMISSAO_MENSAL NUMERIC(15,2),
    META_DIARIA NUMERIC(15,2), META_MENSAL NUMERIC(15,2),
    SERVICO_MENSAL NUMERIC(15,2), COMISSAO_SV_MENSAL NUMERIC(15,2)
)
AS
declare variable MT_D numeric(15,2); declare variable MT_M numeric(15,2);
declare variable VEND_D numeric(15,2); declare variable VEND_M numeric(15,2);
declare variable COM_D numeric(15,2); declare variable COM_M numeric(15,2);
declare variable SERV_M numeric(15,2); declare variable COM_SV_M numeric(15,2);
BEGIN
    select FUNCIONARIOS.META_DIARIA, FUNCIONARIOS.META_MENSAL,
    sum((case when ((ESTOQUE.es = 1) or (ESTOQUE.tipo = 3)) then ESTOQUE.valor_total when ((ESTOQUE.es = 2) and (NATUREZA_OPERACAO.processo = 2)) then (ESTOQUE.valor_total*-1) end) - (((case when ((ESTOQUE.es = 1) or (ESTOQUE.tipo = 3)) then ESTOQUE.valor_total when ((ESTOQUE.es = 2) and (NATUREZA_OPERACAO.processo = 2)) then (ESTOQUE.valor_total*-1) end)*PEDIDOS.desconto)/100)),
    sum((case when ((ESTOQUE.es = 1) or (ESTOQUE.tipo = 3)) then ESTOQUE.valor_comissao when ((ESTOQUE.es = 2) and (NATUREZA_OPERACAO.processo = 2)) then (ESTOQUE.valor_comissao*-1) end))
    from ESTOQUE inner join PEDIDOS on (PEDIDOS.ID_PEDIDO = ESTOQUE.ID_PEDIDO)
    left join FUNCIONARIOS on (FUNCIONARIOS.ID_FUNCIONARIO = PEDIDOS.id_vendedor)
    left join natureza_operacao on (natureza_operacao.id_natureza = pedidos.id_natureza)
    where (natureza_operacao.calc_comissao = 1) and (extract(month from PEDIDOS.data_vencimento) = :MES) and (extract(year from PEDIDOS.data_vencimento) = :ANO)
    and (PEDIDOS.ID_VENDEDOR = :VENDEDOR) and (PEDIDOS.ID_DEPTO = :EMPRESA) and (PEDIDOS.TIPO = 1) and (PEDIDOS.STATUS = 2) and (ESTOQUE.STATUS <> 9) and (ESTOQUE.movc = 1)
    group by FUNCIONARIOS.META_DIARIA, FUNCIONARIOS.META_MENSAL into :MT_D, :MT_M, :VEND_M, :COM_M;

    select sum((case when ((ESTOQUE.es = 1) or (ESTOQUE.tipo = 3)) then ESTOQUE.valor_total when ((ESTOQUE.es = 2) and (NATUREZA_OPERACAO.processo = 2)) then (ESTOQUE.valor_total*-1) end) - (((case when ((ESTOQUE.es = 1) or (ESTOQUE.tipo = 3)) then ESTOQUE.valor_total when ((ESTOQUE.es = 2) and (NATUREZA_OPERACAO.processo = 2)) then (ESTOQUE.valor_total*-1) end)*PEDIDOS.desconto)/100)),
    sum((case when ((ESTOQUE.es = 1) or (ESTOQUE.tipo = 3)) then ESTOQUE.valor_comissao when ((ESTOQUE.es = 2) and (NATUREZA_OPERACAO.processo = 2)) then (ESTOQUE.valor_comissao*-1) end))
    from ESTOQUE inner join PEDIDOS on (PEDIDOS.ID_PEDIDO = ESTOQUE.ID_PEDIDO) left join FUNCIONARIOS on (FUNCIONARIOS.ID_FUNCIONARIO = PEDIDOS.id_vendedor)
    left join natureza_operacao on (natureza_operacao.id_natureza = pedidos.id_natureza)
    where (natureza_operacao.calc_comissao = 1) and ((PEDIDOS.data_vencimento >= :DATA) and (PEDIDOS.data_vencimento <= :DATA))
    and (PEDIDOS.ID_VENDEDOR = :VENDEDOR) and (PEDIDOS.ID_DEPTO = :EMPRESA) and (PEDIDOS.TIPO = 1) and (PEDIDOS.STATUS = 2) and (ESTOQUE.STATUS <> 9) and (ESTOQUE.movc = 1)
    into :VEND_D, :COM_D;

    select sum(LISTAPEDIDOS_ITENS.VALOR_TOTAL), sum(((LISTAPEDIDOS_ITENS.VALOR_TOTAL*(case when PRODUTOS.forca_comissao = 1 then PRODUTOS.comissao else FUNCIONARIOS.comissao end))/100))
    from LISTAPEDIDOS_ITENS left join PRODUTOS on (PRODUTOS.ID_PRODUTO = LISTAPEDIDOS_ITENS.ID_PRODUTO)
    left join FUNCIONARIOS on (FUNCIONARIOS.ID_FUNCIONARIO = LISTAPEDIDOS_ITENS.id_tecnico) left join NATUREZA_OPERACAO on (natureza_operacao.id_natureza = LISTAPEDIDOS_ITENS.id_natureza)
    where (natureza_operacao.calc_comissao = 1) and ((LISTAPEDIDOS_ITENS.tipo_item = 3) or (LISTAPEDIDOS_ITENS.tipo_item = 6)) and (extract(month from LISTAPEDIDOS_ITENS.data_vencimento) = :MES) and (extract(year from LISTAPEDIDOS_ITENS.data_vencimento) = :ANO)
    and (LISTAPEDIDOS_ITENS.id_tecnico = :VENDEDOR) and (LISTAPEDIDOS_ITENS.ID_DEPTO = :EMPRESA) and (LISTAPEDIDOS_ITENS.TIPO = 1) and (LISTAPEDIDOS_ITENS.STATUS = 2)
    into :SERV_M, :COM_SV_M;

    VENDA_DIARIA = coalesce(:VEND_D, 0); VENDA_MENSAL = coalesce(:VEND_M, 0);
    COMISSAO_DIARIA = coalesce(:COM_D, 0); COMISSAO_MENSAL = coalesce(:COM_M, 0);
    META_DIARIA = coalesce(:MT_D, 0); META_MENSAL = coalesce(:MT_M, 0);
    SERVICO_MENSAL = coalesce(:SERV_M, 0); COMISSAO_SV_MENSAL = coalesce(:COM_SV_M, 0);
    SUSPEND;
END";

            var mobMinhasVendasRSql = @"
EXECUTE BLOCK (
    VENDEDOR INTEGER = @VENDEDOR,
    DATAI DATE = @DATAI,
    DATAF DATE = @DATAF,
    DIA DATE = @DIA,
    EMPRESA INTEGER = @EMPRESA,
    DEPTO INTEGER = @DEPTO
)
RETURNS (
    TOTAL_DIARIO NUMERIC(15,2), TOTAL_MENSAL NUMERIC(15,2),
    COMISSAO_DIARIA NUMERIC(15,2), COMISSAO_MENSAL NUMERIC(15,2)
)
AS
declare variable COM_D decimal(15,2); declare variable COM_M decimal(15,2);
declare variable TOT_V_D decimal(15,2); declare variable TOT_V_M decimal(15,2);
declare variable TP_COM smallint;
BEGIN
    select COMISSAO_TIPO from config where ID_EMPRESA = :EMPRESA into :TP_COM;
    if (TP_COM = 1) then BEGIN
        Select SUM(VALOR_PAGO), SUM(COMISSAO_PAGAR) from REL_IC_COMISSAO2 WHERE ((DATA_PAGAMENTO >= :DATAI) AND (DATA_PAGAMENTO <= :DATAF)) AND (ID_VENDEDOR = :VENDEDOR) AND (ID_DEPTO = :DEPTO) into :TOT_V_M, :COM_M;
        Select SUM(VALOR_PAGO), SUM(COMISSAO_PAGAR) from REL_IC_COMISSAO2 WHERE (DATA_PAGAMENTO = :DIA) AND (ID_VENDEDOR = :VENDEDOR) AND (ID_DEPTO = :DEPTO) into :TOT_V_D, :COM_D;
    END
    if (TP_COM = 2) then BEGIN
        Select SUM(VALOR_PAGO), SUM(COMISSAO_PAGAR) from REL_IC_COMISSAO_ITEM2 WHERE ((DATA_PAGAMENTO >= :DATAI) AND (DATA_PAGAMENTO <= :DATAF)) AND (ID_VENDEDOR = :VENDEDOR) AND (ID_DEPTO = :DEPTO) into :TOT_V_M, :COM_M;
        Select SUM(VALOR_PAGO), SUM(COMISSAO_PAGAR) from REL_IC_COMISSAO_ITEM2 WHERE (DATA_PAGAMENTO = :DIA) AND (ID_VENDEDOR = :VENDEDOR) AND (ID_DEPTO = :DEPTO) into :TOT_V_D, :COM_D;
    END
    if (TP_COM = 3) then BEGIN
        Select SUM(VALOR_PAGO), SUM(COMISSAO_PAGAR) from REL_IC_COMISSAO_VAR2 WHERE ((DATA_PAGAMENTO >= :DATAI) AND (DATA_PAGAMENTO <= :DATAF)) AND (ID_VENDEDOR = :VENDEDOR) AND (ID_DEPTO = :DEPTO) into :TOT_V_M, :COM_M;
        Select SUM(VALOR_PAGO), SUM(COMISSAO_PAGAR) from REL_IC_COMISSAO_VAR2 WHERE (DATA_PAGAMENTO = :DIA) AND (ID_VENDEDOR = :VENDEDOR) AND (ID_DEPTO = :DEPTO) into :TOT_V_D, :COM_D;
    END
    COMISSAO_DIARIA = coalesce(:COM_D, 0); COMISSAO_MENSAL = coalesce(:COM_M, 0);
    TOTAL_DIARIO = coalesce(:TOT_V_D, 0); TOTAL_MENSAL = coalesce(:TOT_V_M, 0);
    SUSPEND;
END";

            // [FIX] Dicionário: branchId → lista de KPIs daquela filial.
            // Cada filial recebe um push separado com seu próprio branchId.
            // Isso garante isolamento no Redis por filial (cada app só vê sua filial).
            var kpiByBranch = new Dictionary<Guid, List<object>>();

            foreach (var seller in sellers)
            {
                var sellerId = Convert.ToInt32(seller["ID_FUNCIONARIO"]);
                
                var branchesToSync = _cachedBranches != null && _cachedBranches.Count > 0 
                    ? _cachedBranches 
                    : new List<BranchDto> { new BranchDto(Guid.Empty, "Default", null, Convert.ToInt32(seller["ID_EMPRESA"]), 1, 1, true) };

                foreach (var branch in branchesToSync)
                {
                    if (branch.ErpDeptoPadrao <= 0)
                    {
                        _logger.LogWarning("[CatalogSync/Performance] Filial {BranchName} ignorada na performance por possuir ErpDeptoPadrao inválido ({Depto}).", branch.Name, branch.ErpDeptoPadrao);
                        continue;
                    }

                    try
                    {
                        var mainResult = await _firebird.QueryAsync(
                            mobMinhasVendasSql,
                            new Dictionary<string, object?>
                            {
                                { "@VENDEDOR", sellerId },
                                { "@MES", month },
                                { "@ANO", year },
                                { "@DATA", today },
                                { "@EMPRESA", branch.ErpDeptoPadrao }
                            }, ct);

                        var rangeResult = await _firebird.QueryAsync(
                            mobMinhasVendasRSql,
                            new Dictionary<string, object?>
                            {
                                { "@VENDEDOR", sellerId },
                                { "@DATAI", firstDay },
                                { "@DATAF", lastDay },
                                { "@DIA", today },
                                { "@EMPRESA", branch.ErpEmpresaId },
                                { "@DEPTO", branch.ErpDeptoPadrao }
                            }, ct);

                        var main  = mainResult.FirstOrDefault()  ?? new();
                        var range = rangeResult.FirstOrDefault() ?? new();

                        var kpi = new
                        {
                            sellerId,
                            branchId  = branch.Id != Guid.Empty ? (object)branch.Id : null,
                            empresaId = branch.ErpEmpresaId,
                            deptoId   = branch.ErpDeptoPadrao,
                            month,
                            year,
                            syncedAt        = now.ToString("o"),
                            vendaDiaria     = ToDouble(main,  "VENDA_DIARIA"),
                            vendaMensal     = ToDouble(main,  "VENDA_MENSAL"),
                            comissaoDiaria  = ToDouble(main,  "COMISSAO_DIARIA"),
                            comissaoMensal  = ToDouble(main,  "COMISSAO_MENSAL"),
                            metaDiaria      = ToDouble(main,  "META_DIARIA"),
                            metaMensal      = ToDouble(main,  "META_MENSAL"),
                            servicoMensal   = ToDouble(main,  "SERVICO_MENSAL"),
                            comissaoSvMensal= ToDouble(main,  "COMISSAO_SV_MENSAL"),
                            totalDiario     = ToDouble(range, "TOTAL_DIARIO"),
                            totalMensal     = ToDouble(range, "TOTAL_MENSAL"),
                            comissaoDiariaR = ToDouble(range, "COMISSAO_DIARIA"),
                            comissaoMensalR = ToDouble(range, "COMISSAO_MENSAL"),
                        };

                        // Agrupa por branchId para push isolado por filial
                        var branchKey = branch.Id != Guid.Empty ? branch.Id : Guid.Empty;
                        if (!kpiByBranch.ContainsKey(branchKey))
                            kpiByBranch[branchKey] = new List<object>();
                        kpiByBranch[branchKey].Add(kpi);
                    }
                    catch (Exception ex)
                    {
                        _logger.LogWarning("[CatalogSync/Performance] Erro seller {Id} branch {Branch}: {Error}", sellerId, branch.Name, ex.Message);
                    }
                } // End foreach branch
            } // End foreach seller

            // [FIX] Push separado por filial — cada filial com seu próprio branchId.
            // Garante isolamento no Redis: app de LOJA 2 encontra dados de LOJA 2,
            // app de PIVETA DIST encontra dados de PIVETA DIST. Não há cruzamento.
            var totalKpis = 0;
            var allOk = true;
            foreach (var (branchId, branchKpis) in kpiByBranch)
            {
                Guid? pushBranchId = branchId != Guid.Empty ? branchId : (Guid?)null;
                var branchName = _cachedBranches?.FirstOrDefault(b => b.Id == branchId)?.Name ?? branchId.ToString();
                var ok = await _vps.PushPerformanceAsync(branchKpis, pushBranchId, ct);
                _logger.LogInformation("[CatalogSync/Performance] Filial '{Branch}': {Count} KPIs enviados. OK={Ok}",
                    branchName, branchKpis.Count, ok);
                totalKpis += branchKpis.Count;
                if (!ok) allOk = false;
            }

            if (totalKpis > 0)
            {
                _status.Update("Performance", totalKpis, DateTime.Now, allOk ? null : "Falha parcial no push");
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
