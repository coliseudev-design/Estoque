using System.Data;
using FirebirdSql.Data.FirebirdClient;
using ColiseuSpeed.Worker.Config;
using Microsoft.Extensions.Options;

namespace ColiseuSpeed.Worker.Services;

/// <summary>
/// Serviço de acesso ao banco Firebird do ERP local.
///
/// Gerencia o pool de conexões e provê métodos assíncronos para
/// query e execução de comandos SQL e stored procedures.
///
/// Rule-02 (Async): toda I/O com banco é async — nunca bloqueia o event loop.
/// Rule-03 (Multi-tenant): queries devem filtrar por empresa quando aplicável.
/// </summary>
public sealed class FirebirdService : IAsyncDisposable
{
    private readonly FirebirdOptions          _baseOptions;
    private readonly IdentityApiClient        _identityClient;
    private readonly Guid                     _tenantId;
    private readonly ILogger<FirebirdService> _logger;
    private readonly SemaphoreSlim            _lock = new(1, 1);
    private string?                           _connectionString;

    public FirebirdService(
        IOptions<FirebirdOptions> options,
        IOptions<IdentityApiOptions> identityOptions,
        IdentityApiClient identityClient,
        ILogger<FirebirdService> logger)
    {
        _baseOptions      = options.Value;
        _tenantId         = identityOptions.Value.TenantId;
        _identityClient   = identityClient;
        _logger           = logger;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Conexão
    // ─────────────────────────────────────────────────────────────────────────

    private async Task<string> GetConnectionStringAsync(CancellationToken ct)
    {
        if (_connectionString is not null) return _connectionString;

        // SUGGESTION-2 fix: timeout para não bloquear indefinidamente se o Identity API travar
        if (!await _lock.WaitAsync(TimeSpan.FromSeconds(10), ct))
            throw new TimeoutException("[Firebird] Timeout de 10s aguardando lock de inicialização. Identity API pode estar indisponível.");

        try
        {
            if (_connectionString is not null) return _connectionString;

            // Tenta obter credenciais dinâmicas do Identity API
            if (_tenantId != Guid.Empty)
            {
                var config = await _identityClient.GetFirebirdConfigAsync(_tenantId, ct);
                if (config is not null && !string.IsNullOrEmpty(config.Password))
                {
                    _baseOptions.Host     = config.Host;
                    _baseOptions.Database = config.Database;
                    _baseOptions.User     = config.User;
                    _baseOptions.Password = config.Password;
                    _logger.LogInformation("[Firebird] Credenciais carregadas dinamicamente via Identity. Host: {Host}, Database: {Db}",
                        config.Host, config.Database);
                }
                else
                {
                    _logger.LogWarning("[Firebird] Identity API indisponível externamente. Usando credenciais estáticas do appsettings.json.");
                }
            }

            // Validação mínima antes de conectar
            if (string.IsNullOrEmpty(_baseOptions.Database))
                throw new InvalidOperationException("Firebird:Database não configurado no appsettings.json.");
            if (string.IsNullOrEmpty(_baseOptions.Password))
                throw new InvalidOperationException("Firebird:Password não configurado no appsettings.json.");

            _connectionString = _baseOptions.BuildConnectionString();
            // BLOCKER-1 fix: nunca logar User nem Password. Apenas Host e Database
            // para não vazar credenciais em logs de produção (Rule-04 Secrets Vault).
            _logger.LogInformation("[Firebird] Conectado. Host: {Host} | Database: {Db}",
                _baseOptions.Host, _baseOptions.Database);
            return _connectionString;
        }
        finally
        {
            _lock.Release();
        }
    }

    /// <summary>Abre e retorna uma nova conexão com o Firebird.</summary>
    private async Task<FbConnection> GetConnectionAsync(CancellationToken ct = default)
    {
        var connStr = await GetConnectionStringAsync(ct);
        var conn = new FbConnection(connStr);
        await conn.OpenAsync(ct);
        return conn;
    }

    /// <summary>Verifica se o banco está acessível.</summary>
    public async Task<bool> IsAvailableAsync(CancellationToken ct = default)
    {
        try
        {
            await using var conn = await GetConnectionAsync(ct);
            return conn.State == ConnectionState.Open;
        }
        catch (Exception ex)
        {
            _logger.LogWarning("[Firebird] Banco indisponível: {Error}", ex.Message);
            return false;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Query — SELECT
    // ─────────────────────────────────────────────────────────────────────────

    /// <summary>
    /// Executa um SELECT e retorna todas as linhas como lista de dicionários.
    ///
    /// Exemplo:
    ///   var rows = await fb.QueryAsync("SELECT ID_PRODUTO, DESCRICAO FROM MOB_PRODUTOS");
    /// </summary>
    /// <param name="sql">Consulta SQL com parâmetros opcionais (@param).</param>
    /// <param name="parameters">Parâmetros nomeados (ex: @since → DateTime).</param>
    public async Task<List<Dictionary<string, object?>>> QueryAsync(
        string sql,
        Dictionary<string, object?>? parameters = null,
        CancellationToken ct = default)
    {
        var results = new List<Dictionary<string, object?>>();

        await using var conn = await GetConnectionAsync(ct);
        await using var cmd  = new FbCommand(sql, conn);

        AddParameters(cmd, parameters);

        await using var reader = await cmd.ExecuteReaderAsync(ct);
        while (await reader.ReadAsync(ct))
        {
            var row = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
            for (int i = 0; i < reader.FieldCount; i++)
                row[reader.GetName(i)] = reader.IsDBNull(i) ? null : reader.GetValue(i);

            results.Add(row);
        }

        return results;
    }

    /// <summary>
    /// Executa um SELECT e retorna o primeira linha, ou null se vazio.
    /// </summary>
    public async Task<Dictionary<string, object?>?> QuerySingleAsync(
        string sql,
        Dictionary<string, object?>? parameters = null,
        CancellationToken ct = default)
    {
        var rows = await QueryAsync(sql, parameters, ct);
        return rows.Count > 0 ? rows[0] : null;
    }

    /// <summary>
    /// Executa um SELECT e captura falhas (útil para views dinâmicas ou opcionais).
    /// </summary>
    public async Task<(bool success, List<Dictionary<string, object?>> data)> QueryRawAsync(
        string sql,
        Dictionary<string, object?>? parameters = null,
        CancellationToken ct = default)
    {
        try
        {
            var results = await QueryAsync(sql, parameters, ct);
            return (true, results);
        }
        catch (Exception ex)
        {
            _logger.LogWarning("[Firebird/Raw] Query ignorada/falha: {Msg}", ex.Message);
            return (false, new List<Dictionary<string, object?>>());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Execute — INSERT / UPDATE / DELETE / EXECUTE PROCEDURE
    // ─────────────────────────────────────────────────────────────────────────

    /// <summary>
    /// Executa um comando DDL/DML e retorna o número de linhas afetadas.
    /// </summary>
    public async Task<int> ExecuteAsync(
        string sql,
        Dictionary<string, object?>? parameters = null,
        CancellationToken ct = default)
    {
        await using var conn = await GetConnectionAsync(ct);
        await using var cmd  = new FbCommand(sql, conn);

        AddParameters(cmd, parameters);
        return await cmd.ExecuteNonQueryAsync(ct);
    }

    /// <summary>
    /// Executa uma stored procedure do ERP e retorna o resultado (se houver).
    ///
    /// Exemplo:
    ///   await fb.ExecuteProcedureAsync("MOB_CADASTRAR_PEDIDO", new() {
    ///     { "@ID_PEDIDO",   pedidoId },
    ///     { "@ID_CLIENTE",  clienteId },
    ///     { "@TOTAL",       total }
    ///   });
    /// </summary>
    public async Task<List<Dictionary<string, object?>>> ExecuteProcedureAsync(
        string procedureName,
        Dictionary<string, object?>? parameters = null,
        CancellationToken ct = default)
    {
        // Defesa contra SQL injection: procedureName deve ser identificador válido
        if (!System.Text.RegularExpressions.Regex.IsMatch(procedureName, @"^[A-Za-z_][A-Za-z0-9_]*$"))
            throw new ArgumentException($"Nome de procedure inválido: {procedureName}");

        var sql = $"EXECUTE PROCEDURE {procedureName}";
        if (parameters?.Count > 0)
        {
            var paramList = string.Join(", ", parameters.Keys.Select(k => k.StartsWith("@") ? k : $"@{k}"));
            sql = $"EXECUTE PROCEDURE {procedureName}({paramList})";
        }

        return await QueryAsync(sql, parameters, ct);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Transação
    // ─────────────────────────────────────────────────────────────────────────

    /// <summary>
    /// Executa um bloco de ações dentro de uma transação.
    /// Faz COMMIT se sem exceção; ROLLBACK automático em caso de falha.
    ///
    /// Exemplo:
    ///   await fb.TransactionAsync(async (cmd, ct) => {
    ///       cmd.CommandText = "INSERT INTO PEDIDOS ...";
    ///       await cmd.ExecuteNonQueryAsync(ct);
    ///   });
    /// </summary>
    public async Task TransactionAsync(
        Func<FbCommand, CancellationToken, Task> action,
        CancellationToken ct = default)
    {
        await using var conn = await GetConnectionAsync(ct);
        await using var txn  = await conn.BeginTransactionAsync(ct) as FbTransaction
                               ?? throw new InvalidOperationException("Falha ao iniciar transação.");

        await using var cmd = new FbCommand { Connection = conn, Transaction = txn };

        try
        {
            await action(cmd, ct);
            await txn.CommitAsync(ct);
        }
        catch (OperationCanceledException)
        {
            _logger.LogWarning("[Firebird/GracefulShutdown] Operação interrompida (Ex: Host caindo). Forçando ROLLBACK de segurança.");
            await txn.RollbackAsync(CancellationToken.None); // Não usa ct aqui pois já está cancelado
            throw;
        }
        catch
        {
            await txn.RollbackAsync(CancellationToken.None);
            throw;
        }
    }

    /// <summary>
    /// Executa um bloco de ações dentro de uma transação, retornando um valor.
    /// A callback recebe a conexão aberta com transação ativa.
    /// Faz COMMIT se sem exceção; ROLLBACK automático em caso de falha.
    /// </summary>
    public async Task<T> ExecuteInTransactionAsync<T>(
        Func<FbConnection, Task<T>> action,
        CancellationToken ct = default)
    {
        await using var conn = await GetConnectionAsync(ct);
        await using var txn  = await conn.BeginTransactionAsync(ct) as FbTransaction
                               ?? throw new InvalidOperationException("Falha ao iniciar transação.");

        try
        {
            var result = await action(conn);
            await txn.CommitAsync(ct);
            return result;
        }
        catch (OperationCanceledException)
        {
            _logger.LogWarning("[Firebird/GracefulShutdown] Operação interrompida (Ex: Host caindo). Forçando ROLLBACK de segurança.");
            await txn.RollbackAsync(CancellationToken.None);
            throw;
        }
        catch
        {
            await txn.RollbackAsync(CancellationToken.None);
            throw;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────────────

    private static void AddParameters(FbCommand cmd, Dictionary<string, object?>? parameters)
    {
        if (parameters is null) return;
        foreach (var (key, value) in parameters)
        {
            var paramName = key.StartsWith("@") ? key[1..] : key;
            cmd.Parameters.AddWithValue(paramName, value ?? DBNull.Value);
        }
    }

    public async ValueTask DisposeAsync()
    {
        // FbConnection usa pool — não há estado a liberar aqui
        await Task.CompletedTask;
    }
}
