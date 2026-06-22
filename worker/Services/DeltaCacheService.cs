using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Linq;
using System.Collections.Generic;
using Dapper;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.Options;
using ColiseuSales.Worker.Config;

namespace ColiseuSales.Worker.Services;

public sealed class DeltaCacheService
{
    private readonly string _dbPath;
    private readonly string _connectionString;

    public DeltaCacheService(IOptions<WorkerOptions> workerOpts)
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        
        var suffix = workerOpts.Value.ServiceSuffix;
        var sanitizedSuffix = SanitizeSuffix(suffix);
        var folderName = string.IsNullOrEmpty(sanitizedSuffix) ? "Worker" : $"Worker_{sanitizedSuffix}";

        var dir = Path.Combine(appData, "ColiseuSales", folderName);
        if (!Directory.Exists(dir))
        {
            Directory.CreateDirectory(dir);
        }
        _dbPath = Path.Combine(dir, "sync_cache.sqlite");
        _connectionString = $"Data Source={_dbPath};Cache=Shared;";
        InitializeDatabase();
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

    private void InitializeDatabase()
    {
        using var connection = new SqliteConnection(_connectionString);
        connection.Open();

        // Configurações críticas para evitar 'database is locked' com múltiplas threads
        connection.Execute("PRAGMA journal_mode=WAL;");
        connection.Execute("PRAGMA busy_timeout=15000;");

        // Criar a tabela se não existir
        var sql = @"
            CREATE TABLE IF NOT EXISTS SyncHashes (
                Entity VARCHAR(50) NOT NULL,
                IdFirebird VARCHAR(50) NOT NULL,
                RowHash VARCHAR(64) NOT NULL,
                SyncedAt DATETIME NOT NULL,
                PRIMARY KEY (Entity, IdFirebird)
            );
        ";
        connection.Execute(sql);
    }

    /// <summary>
    /// Calcula o hash SHA-256 do JSON de uma linha
    /// </summary>
    public string ComputeHash(dynamic row)
    {
        string json = JsonSerializer.Serialize(row);
        using var sha256 = SHA256.Create();
        byte[] bytes = sha256.ComputeHash(Encoding.UTF8.GetBytes(json));
        
        var builder = new StringBuilder();
        for (int i = 0; i < bytes.Length; i++)
        {
            builder.Append(bytes[i].ToString("x2"));
        }
        return builder.ToString();
    }

    /// <summary>
    /// Retorna todos os hashes de uma determinada entidade cadastrados no cache SQLite.
    /// Evita milhares de queries individuais ao banco.
    /// </summary>
    public Dictionary<string, string> GetEntityHashes(string entity)
    {
        using var connection = new SqliteConnection(_connectionString);
        var sql = "SELECT IdFirebird, RowHash FROM SyncHashes WHERE Entity = @Entity";
        var dict = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        
        try
        {
            foreach (var item in connection.Query(sql, new { Entity = entity }))
            {
                string id = item.IdFirebird?.ToString() ?? "";
                string hash = item.RowHash?.ToString() ?? "";
                if (!string.IsNullOrEmpty(id))
                {
                    dict[id] = hash;
                }
            }
        }
        catch (Exception)
        {
            // Fallback: se houver falha, retorna dicionário vazio para recriar o cache
        }
        
        return dict;
    }

    /// <summary>
    /// Salva em lote os hashes após sincronização concluída com sucesso.
    /// Executado em uma única transação SQLite para excelente performance.
    /// </summary>
    public void SaveHashes(string entity, Dictionary<string, string> hashes)
    {
        if (hashes == null || hashes.Count == 0) return;
        
        using var connection = new SqliteConnection(_connectionString);
        connection.Open();
        using var transaction = connection.BeginTransaction();
        
        try
        {
            var sql = @"
                INSERT INTO SyncHashes (Entity, IdFirebird, RowHash, SyncedAt)
                VALUES (@Entity, @IdFirebird, @Hash, @SyncedAt)
                ON CONFLICT(Entity, IdFirebird) DO UPDATE SET
                    RowHash = excluded.RowHash,
                    SyncedAt = excluded.SyncedAt;
            ";
            
            var parameters = hashes.Select(x => new
            {
                Entity = entity,
                IdFirebird = x.Key,
                Hash = x.Value,
                SyncedAt = DateTime.UtcNow
            });
            
            connection.Execute(sql, parameters, transaction: transaction);
            transaction.Commit();
        }
        catch
        {
            transaction.Rollback();
            throw;
        }
    }

    /// <summary>
    /// Verifica se a linha mudou comparando com o Hash salvo localmente.
    /// Retorna true se a linha for nova ou se o hash mudou.
    /// </summary>
    public bool IsChanged(string entity, string idFirebird, string newHash)
    {
        using var connection = new SqliteConnection(_connectionString);
        var sql = "SELECT RowHash FROM SyncHashes WHERE Entity = @Entity AND IdFirebird = @IdFirebird LIMIT 1";
        var savedHash = connection.QueryFirstOrDefault<string>(sql, new { Entity = entity, IdFirebird = idFirebird });

        if (savedHash == null)
            return true; // É novo

        return savedHash != newHash; // True se mudou, False se for idêntico
    }

    /// <summary>
    /// Salva ou atualiza o hash de uma linha após sincronizar com sucesso.
    /// </summary>
    public void SaveHash(string entity, string idFirebird, string hash)
    {
        using var connection = new SqliteConnection(_connectionString);
        var sql = @"
            INSERT INTO SyncHashes (Entity, IdFirebird, RowHash, SyncedAt)
            VALUES (@Entity, @IdFirebird, @Hash, @SyncedAt)
            ON CONFLICT(Entity, IdFirebird) DO UPDATE SET
                RowHash = excluded.RowHash,
                SyncedAt = excluded.SyncedAt;
        ";
        connection.Execute(sql, new { Entity = entity, IdFirebird = idFirebird, Hash = hash, SyncedAt = DateTime.UtcNow });
    }
}
