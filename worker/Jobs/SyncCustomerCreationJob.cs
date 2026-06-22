using FirebirdSql.Data.FirebirdClient;
using ColiseuSales.Worker.Services;

namespace ColiseuSales.Worker.Jobs;

/// <summary>
/// SyncCustomerCreationJob — Busca clientes pendentes na VPS e os cadastra no Firebird.
///
/// Fluxo (mesmo padrão do SyncOrdersJob):
/// 1. GET /api/sync/pending-customers → clientes que o app Flutter cadastrou
/// 2. Para cada cliente: Firebird → MOB_CADASTRA_CLIENTE + busca ID gerado
/// 3. Confirma na VPS com o ERP ID: POST /api/sync/confirm-customer/{id}
/// 4. Em caso de erro: POST /api/sync/error-customer/{id}
///
/// Cadência: compartilha timer com SyncOrdersJob (padrão 1 minuto).
/// Rule-02: totalmente async.
/// </summary>
public sealed class SyncCustomerCreationJob
{
    private readonly FirebirdService                        _firebird;
    private readonly VpsApiClient                           _vps;
    private readonly StatusStore                            _store;
    private readonly ILogger<SyncCustomerCreationJob>       _logger;

    private const int MaxConfirmRetries = 3;

    public SyncCustomerCreationJob(
        FirebirdService                  firebird,
        VpsApiClient                     vps,
        StatusStore                      store,
        ILogger<SyncCustomerCreationJob> logger)
    {
        _firebird = firebird;
        _vps      = vps;
        _store    = store;
        _logger   = logger;
    }

    /// <summary>Executa um ciclo de processamento de clientes pendentes.</summary>
    public async Task RunAsync(CancellationToken ct = default)
    {
        List<Dictionary<string, object?>> customers;
        try
        {
            customers = await _vps.GetPendingCustomersAsync(ct);
        }
        catch (Exception ex)
        {
            _logger.LogError("[CustomerSync] Erro ao buscar clientes pendentes: {Error}", ex.Message);
            return;
        }

        if (customers.Count == 0)
        {
            _logger.LogDebug("[CustomerSync] Nenhum cliente pendente.");
            return;
        }

        _logger.LogInformation("[CustomerSync] {Count} cliente(s) para processar.", customers.Count);

        foreach (var customer in customers)
        {
            await ProcessCustomerAsync(customer, ct);
        }
    }

    private async Task ProcessCustomerAsync(Dictionary<string, object?> customer, CancellationToken ct)
    {
        var pendingId = GetString(customer, "pendingId");
        var name      = GetString(customer, "name");

        _logger.LogInformation("[CustomerSync] Processando cliente {Name} (pendingId={PendingId})",
            name, pendingId);

        // FASE 1 — Inserção no Firebird via MOB_CADASTRA_CLIENTE
        string? erpCustomerId;
        try
        {
            erpCustomerId = await InsertIntoFirebirdAsync(customer, ct);
        }
        catch (Exception ex)
        {
            var msgErro = $"[Clientes] ❌ Erro ao cadastrar {name}: {ex.Message}";
            _store.AppendLog(msgErro);
            _store.Update("Clientes", 0, DateTime.Now, error: ex.Message);
            _logger.LogError("[CustomerSync] Erro Firebird ao cadastrar {Name}: {Error}",
                name, ex.Message);

            try { await _vps.ReportCustomerErrorAsync(pendingId, ex.Message, ct); }
            catch { /* VPS pode estar instável — ignora */ }
            return;
        }

        // FASE 2 — Confirmação na VPS
        await ConfirmWithRetryAsync(pendingId, erpCustomerId ?? "unknown", ct);
    }

    /// <summary>
    /// Executa MOB_CADASTRA_CLIENTE no Firebird e busca o ID do cliente recém-criado.
    ///
    /// MOB_CADASTRA_CLIENTE(TIPOPESSOA, NOME, CPFCNPJ, EMAIL, TELEFONE,
    ///   CEP, CIDADE, UF, ENDERECO, NUMERO, BAIRRO, IDUSUARIO, TABELAPRECO,
    ///   COMPLEMENTO, INSCRICAOESTADUAL)
    /// </summary>
    private async Task<string?> InsertIntoFirebirdAsync(Dictionary<string, object?> c, CancellationToken ct)
    {
        var name   = GetString(c, "name")?.Trim().ToUpperInvariant() ?? "";
        var cnpj   = FormatCpfCnpj(GetString(c, "cnpj"));
        var phone  = FormatPhone(GetString(c, "phone"));
        var email  = GetString(c, "email");
        var cep    = FormatCep(GetString(c, "zipCode") ?? GetString(c, "cep"));
        var city   = GetString(c, "city")?.Trim().ToUpperInvariant();
        var state  = GetString(c, "state")?.Trim().ToUpperInvariant();
        var street = GetString(c, "street")?.Trim().ToUpperInvariant();
        var number = GetString(c, "streetNumber")?.Trim().ToUpperInvariant();
        var neighborhood = GetString(c, "neighborhood")?.Trim().ToUpperInvariant();
        var sellerId     = GetInt(c, "sellerId", 1);
        var complement   = GetString(c, "complement")?.Trim().ToUpperInvariant();
        var ie           = GetString(c, "ie")?.Trim().ToUpperInvariant();

        // TIPOPESSOA: 1=PF, 2=PJ
        var cnpjDigits = System.Text.RegularExpressions.Regex.Replace(cnpj ?? "", @"\D", "");
        var tipoPessoa = cnpjDigits.Length > 11 ? 2 : 1;

        // Executa a procedure de cadastro
        await _firebird.TransactionAsync(async (cmd, innerCt) =>
        {
            cmd.CommandText = @"EXECUTE PROCEDURE MOB_CADASTRA_CLIENTE(
                @TIPOPESSOA, @NOME, @CPFCNPJ, @EMAIL, @TELEFONE,
                @CEP, @CIDADE, @UF, @ENDERECO, @NUMERO, @BAIRRO,
                @IDUSUARIO, @TABELAPRECO, @COMPLEMENTO, @INSCRICAOESTADUAL)";

            cmd.Parameters.Clear();
            cmd.Parameters.AddWithValue("@TIPOPESSOA",          tipoPessoa);
            cmd.Parameters.AddWithValue("@NOME",                name);
            cmd.Parameters.AddWithValue("@CPFCNPJ",             cnpj ?? "");
            cmd.Parameters.AddWithValue("@EMAIL",                email ?? "");
            cmd.Parameters.AddWithValue("@TELEFONE",             phone ?? "");
            cmd.Parameters.AddWithValue("@CEP",                  cep ?? "");
            cmd.Parameters.AddWithValue("@CIDADE",               city ?? "");
            cmd.Parameters.AddWithValue("@UF",                   state ?? "");
            cmd.Parameters.AddWithValue("@ENDERECO",             street ?? "");
            cmd.Parameters.AddWithValue("@NUMERO",               number ?? "");
            cmd.Parameters.AddWithValue("@BAIRRO",               neighborhood ?? "");
            cmd.Parameters.AddWithValue("@IDUSUARIO",            sellerId);
            cmd.Parameters.AddWithValue("@TABELAPRECO",          1);
            cmd.Parameters.AddWithValue("@COMPLEMENTO",          complement ?? "");
            cmd.Parameters.AddWithValue("@INSCRICAOESTADUAL",    ie ?? "");

            await cmd.ExecuteNonQueryAsync(innerCt);
        }, ct);

        // Busca ID do cliente recém-criado (por CPF/CNPJ ou nome)
        string? erpId = null;

        if (!string.IsNullOrEmpty(cnpj))
        {
            var rows = await _firebird.QueryAsync(
                @"SELECT FIRST 1 ID_CLIENTE FROM MOB_LISTACLIENTES
                  WHERE CPF_CNPJ = @DOC ORDER BY ID_CLIENTE DESC",
                new Dictionary<string, object?> { { "@DOC", cnpj } }, ct);

            if (rows.Count > 0)
                erpId = rows[0].Values.First()?.ToString();
        }

        if (erpId == null)
        {
            var rows = await _firebird.QueryAsync(
                @"SELECT FIRST 1 ID_CLIENTE FROM MOB_LISTACLIENTES
                  WHERE UPPER(TRIM(NOME)) = @NOME ORDER BY ID_CLIENTE DESC",
                new Dictionary<string, object?> { { "@NOME", name } }, ct);

            if (rows.Count > 0)
                erpId = rows[0].Values.First()?.ToString();
        }

        // Atualiza celular em CLIENTES_DADOS
        if (erpId != null && !string.IsNullOrEmpty(phone))
        {
            try
            {
                await _firebird.QueryAsync(
                    "UPDATE CLIENTES_DADOS SET CELULAR = @PHONE WHERE ID_CLIENTE = @ID",
                    new Dictionary<string, object?>
                    {
                        { "@PHONE", phone },
                        { "@ID", int.Parse(erpId) }
                    }, ct);
                _logger.LogDebug("[CustomerSync] CELULAR atualizado para cliente {Id}", erpId);
            }
            catch (Exception ex)
            {
                _logger.LogWarning("[CustomerSync] Falha ao atualizar CELULAR: {Error}", ex.Message);
            }
        }

        _logger.LogInformation("[CustomerSync] Cliente cadastrado no ERP. Name={Name}, ERP_ID={Id}", name, erpId);
        return erpId;
    }

    /// <summary>Confirma o cadastro na VPS com retry exponencial.</summary>
    private async Task ConfirmWithRetryAsync(string pendingId, string erpCustomerId, CancellationToken ct)
    {
        for (int attempt = 1; attempt <= MaxConfirmRetries; attempt++)
        {
            try
            {
                var ok = await _vps.ConfirmCustomerAsync(pendingId, erpCustomerId, ct);
                if (ok)
                {
                    _logger.LogInformation(
                        "[CustomerSync] Cliente {PendingId} confirmado (ERP={ErpId}, tentativa {Attempt}).",
                        pendingId, erpCustomerId, attempt);
                    return;
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(
                    "[CustomerSync] Tentativa {Attempt}/{Max} de confirmar {PendingId} falhou: {Error}",
                    attempt, MaxConfirmRetries, pendingId, ex.Message);
            }

            if (attempt < MaxConfirmRetries)
                await Task.Delay(TimeSpan.FromSeconds(Math.Pow(2, attempt)), ct);
        }

        _logger.LogError(
            "[CustomerSync] Cliente {PendingId} cadastrado no ERP (ID={ErpId}) " +
            "mas NÃO confirmado na VPS após {Max} tentativas.",
            pendingId, erpCustomerId, MaxConfirmRetries);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private static string? GetString(Dictionary<string, object?> d, string key)
        => d.TryGetValue(key, out var v) && v != null ? v.ToString() : null;

    private static int GetInt(Dictionary<string, object?> d, string key, int fallback = 0)
        => d.TryGetValue(key, out var v) && v != null && int.TryParse(v.ToString(), out var i) ? i : fallback;

    /// <summary>Formata CPF (000.000.000-00) ou CNPJ (00.000.000/0000-00).</summary>
    private static string? FormatCpfCnpj(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return null;
        var digits = System.Text.RegularExpressions.Regex.Replace(raw, @"\D", "");
        return digits.Length switch
        {
            11 => $"{digits[..3]}.{digits[3..6]}.{digits[6..9]}-{digits[9..]}",
            14 => $"{digits[..2]}.{digits[2..5]}.{digits[5..8]}/{digits[8..12]}-{digits[12..]}",
            _  => digits
        };
    }

    /// <summary>Formata telefone (DD)-NNNNN-NNNN (máscara ERP).</summary>
    private static string? FormatPhone(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return null;
        var digits = System.Text.RegularExpressions.Regex.Replace(raw, @"\D", "");
        return digits.Length switch
        {
            11 => $"({digits[..2]})-{digits[2..7]}-{digits[7..]}",
            10 => $"({digits[..2]})-{digits[2..6]}-{digits[6..]}",
            _  => digits
        };
    }

    /// <summary>Formata CEP 00000-000.</summary>
    private static string? FormatCep(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return null;
        var digits = System.Text.RegularExpressions.Regex.Replace(raw, @"\D", "");
        return digits.Length == 8 ? $"{digits[..5]}-{digits[5..]}" : digits;
    }
}
