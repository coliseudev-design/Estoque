using Dapper;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using ColiseuSpeed.Worker.Config;
using ColiseuSpeed.Worker.Services;

namespace ColiseuSpeed.Worker.Services;

/// <summary>
/// Serviço de rastreamento de alterações (Change Tracking)
/// Permite que os jobs verifiquem se houve novas alterações no Firebird antes de rodarem,
/// salvando a última posição de processamento no banco SQLite local.
/// </summary>
public sealed class ChangeTrackerService
{
    private readonly FirebirdService _firebird;
    private readonly string _sqliteConnString;
    private readonly ILogger<ChangeTrackerService> _logger;

    public ChangeTrackerService(FirebirdService firebird, IOptions<WorkerOptions> workerOpts, ILogger<ChangeTrackerService> logger)
    {
        _firebird = firebird;
        _logger = logger;

        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        
        var suffix = workerOpts.Value.ServiceSuffix;
        var sanitizedSuffix = SanitizeSuffix(suffix);
        var folderName = string.IsNullOrEmpty(sanitizedSuffix) ? "Worker" : $"Worker_{sanitizedSuffix}";
        
        var dir = Path.Combine(appData, "ColiseuSpeed", folderName);
        if (!Directory.Exists(dir))
        {
            Directory.CreateDirectory(dir);
        }
        var dbPath = Path.Combine(dir, "sync_cache.sqlite");
        _sqliteConnString = $"Data Source={dbPath};Cache=Shared;";

        InitializeSqliteDatabase();
    }

    private static string SanitizeSuffix(string suffix)
    {
        if (string.IsNullOrWhiteSpace(suffix)) return string.Empty;
        var sb = new System.Text.StringBuilder();
        foreach (char c in suffix)
        {
            if (char.IsLetterOrDigit(c) || c == '_' || c == '-')
            {
                sb.Append(c);
            }
        }
        return sb.ToString();
    }

    private void InitializeSqliteDatabase()
    {
        using var connection = new SqliteConnection(_sqliteConnString);
        connection.Open();
        connection.Execute("PRAGMA journal_mode=WAL;");
        connection.Execute("PRAGMA busy_timeout=15000;");

        var sql = @"
            CREATE TABLE IF NOT EXISTS JobSyncPositions (
                JobName VARCHAR(50) NOT NULL PRIMARY KEY,
                LastProcessedLogId INTEGER NOT NULL DEFAULT 0
            );
        ";
        connection.Execute(sql);
    }

    /// <summary>
    /// Verifica se há novas alterações no Firebird para a lista de tabelas informada
    /// </summary>
    public async Task<bool> HasChangesAsync(string jobName, string[] tableNames)
    {
        try
        {
            long? lastId = GetLastProcessedLogId(jobName);

            // Se for a primeira execução (não há registro no SQLite), força a varredura inicial (sweep)
            if (!lastId.HasValue)
            {
                _logger.LogInformation("[ChangeTracker] Primeira execução do Job={JobName}. Forçando varredura inicial.", jobName);
                return true;
            }

            // Se a última posição for negativa, consideramos que há alterações (force full sync)
            if (lastId.Value < 0) return true;

            var tablesInClause = string.Join(",", tableNames.Select(t => $"'{t.ToUpperInvariant()}'"));
            
            // Verifica se existe algum log de alteração não processado para essas tabelas
            var sql = $@"
                SELECT FIRST 1 ID_LOG 
                FROM COLISEU_SYNC_LOG 
                WHERE NOME_TABELA IN ({tablesInClause}) 
                  AND ID_LOG > {lastId.Value}
                ORDER BY ID_LOG ASC";

            var rows = await _firebird.QueryAsync(sql);
            return rows.Count > 0;
        }
        catch (Exception ex)
        {
            // Fallback: se a tabela de log não existir no banco do cliente,
            // permitimos que o job rode normalmente (como query completa + hash no C#).
            _logger.LogWarning("[ChangeTracker] Tabela COLISEU_SYNC_LOG indisponível: {Msg}. Rodando sync completo.", ex.Message);
            return true;
        }
    }

    /// <summary>
    /// Atualiza a posição de leitura do Job para o ID máximo de log atual do Firebird
    /// </summary>
    public async Task UpdateLastProcessedLogIdAsync(string jobName, string[] tableNames)
    {
        try
        {
            var tablesInClause = string.Join(",", tableNames.Select(t => $"'{t.ToUpperInvariant()}'"));
            var sql = $"SELECT MAX(ID_LOG) AS MAX_ID FROM COLISEU_SYNC_LOG WHERE NOME_TABELA IN ({tablesInClause})";
            
            var rows = await _firebird.QueryAsync(sql);
            long maxId = 0;
            if (rows.Count > 0 && rows[0]["MAX_ID"] != DBNull.Value && rows[0]["MAX_ID"] != null)
            {
                maxId = Convert.ToInt64(rows[0]["MAX_ID"]);
            }

            SaveLastProcessedLogId(jobName, maxId);
            _logger.LogDebug("[ChangeTracker] Atualizado Job={JobName} para LastProcessedLogId={MaxId}", jobName, maxId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[ChangeTracker] Erro ao atualizar posição do log para o job {JobName}", jobName);
        }
    }

    /// <summary>
    /// Limpa logs antigos no Firebird (mantendo 7 dias)
    /// </summary>
    public async Task PruneOldLogsAsync()
    {
        try
        {
            _logger.LogInformation("[ChangeTracker] Limpando logs de sincronismo antigos do Firebird (mantendo 7 dias)...");
            var sql = "DELETE FROM COLISEU_SYNC_LOG WHERE DATA_HORA < CURRENT_TIMESTAMP - 7";
            await _firebird.ExecuteAsync(sql);
            _logger.LogInformation("[ChangeTracker] Limpeza de logs concluída com sucesso.");
        }
        catch (Exception ex)
        {
            _logger.LogWarning("[ChangeTracker] Falha na limpeza de logs: {Msg}", ex.Message);
        }
    }

    private long? GetLastProcessedLogId(string jobName)
    {
        using var connection = new SqliteConnection(_sqliteConnString);
        var sql = "SELECT LastProcessedLogId FROM JobSyncPositions WHERE JobName = @JobName";
        return connection.QueryFirstOrDefault<long?>(sql, new { JobName = jobName });
    }

    private void SaveLastProcessedLogId(string jobName, long logId)
    {
        using var connection = new SqliteConnection(_sqliteConnString);
        var sql = @"
            INSERT INTO JobSyncPositions (JobName, LastProcessedLogId)
            VALUES (@JobName, @LogId)
            ON CONFLICT(JobName) DO UPDATE SET
                LastProcessedLogId = excluded.LastProcessedLogId;
        ";
        connection.Execute(sql, new { JobName = jobName, LogId = logId });
    }

    /// <summary>
    /// Zera a leitura de todos os jobs locais para forçar um sincronismo completo geral
    /// </summary>
    public void ResetAllPositions()
    {
        try
        {
            using var connection = new SqliteConnection(_sqliteConnString);
            connection.Execute("DELETE FROM JobSyncPositions");
            _logger.LogInformation("[ChangeTracker] Posições de leitura resetadas para todos os jobs.");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[ChangeTracker] Falha ao resetar posições de leitura");
        }
    }
}
