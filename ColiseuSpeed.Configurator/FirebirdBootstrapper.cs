using FirebirdSql.Data.FirebirdClient;

namespace ColiseuSpeed.Configurator;

/// <summary>
/// Verifica e cria objetos obrigatórios do Coliseu Speed no banco Firebird.
///
/// Objetos verificados:
///   - 5 Stored Procedures (MOB_CADASTRAR_PEDIDO, MOB_CADASTRAR_PEDIDO_ITEM,
///     MOB_CADASTRA_CLIENTE, MINHASVENDAS, MINHASVENDASR)
///   - 12 Views (L_VENDAS_PRODUTO, L_VENDAS_CLIENTE, L_VENDAS_REGIAO,
///     MOB_LISTACLIENTES, MOB_LISTACONTAS, DASH_CLIENTES, DASH_PRODUTOS,
///     DASH_VENDEDORES, DASH_VENDAS, DASH_VENDAS_ITENS, DASH_FINANCEIRO,
///     DASH_FILIAIS)
///   - 9 Colunas customizadas (MOB_ACESSO, MOB_SENHA, etc.)
///   - 1 Generator (PEDIDOS)
///   - 1 Campo controle (ADM_GLOBAL.NR_MOB)
/// </summary>
public sealed class FirebirdBootstrapper
{
    // ── Resultado de cada item verificado ───────────────────────────────────
    public enum ItemStatus { AlreadyExists, Created, Error, RequiresUpdate }

    public record BootstrapItem(string Type, string Name, ItemStatus Status, string? ErrorMessage = null);

    // ── Conexão ────────────────────────────────────────────────────────────
    private readonly string _connectionString;

    public FirebirdBootstrapper(string host, int port, string database,
                                 string user, string password, bool wireCrypt)
    {
        var csb = new FbConnectionStringBuilder
        {
            DataSource = host,
            Port = port,
            Database = database,
            UserID = user,
            Password = password,
            Charset = "NONE",
            Dialect = 3,
            WireCrypt = wireCrypt ? FbWireCrypt.Enabled : FbWireCrypt.Disabled,
        };
        _connectionString = csb.ToString();
    }

    // ── API pública ────────────────────────────────────────────────────────

    /// <summary>
    /// Fase 1: Diagnóstico — retorna lista de itens com status (existe ou falta).
    /// Não modifica o banco.
    /// </summary>
    public async Task<List<BootstrapItem>> DiagnoseAsync()
    {
        var results = new List<BootstrapItem>();

        await using var conn = new FbConnection(_connectionString);
        await conn.OpenAsync();

        // Stored Procedures
        var existingProcsSource = await QuerySourcesAsync(conn,
            "SELECT TRIM(RDB$PROCEDURE_NAME), RDB$PROCEDURE_SOURCE FROM RDB$PROCEDURES WHERE RDB$SYSTEM_FLAG = 0");

        foreach (var sp in RequiredProcedures)
        {
            ItemStatus status;
            if (existingProcsSource.TryGetValue(sp.Key, out var dbSource))
            {
                status = IsStandard(sp.Value, dbSource, true, sp.Key) ? ItemStatus.AlreadyExists : ItemStatus.RequiresUpdate;
            }
            else
            {
                status = ItemStatus.Error; // Missing
            }
                
            results.Add(new("SP", sp.Key, status));
        }

        // Views
        var existingViewsSource = await QuerySourcesAsync(conn,
            "SELECT TRIM(RDB$RELATION_NAME), RDB$VIEW_SOURCE FROM RDB$RELATIONS WHERE RDB$VIEW_BLR IS NOT NULL AND RDB$SYSTEM_FLAG = 0");
        foreach (var v in RequiredViews)
        {
            ItemStatus status;
            if (existingViewsSource.TryGetValue(v.Key, out var dbSource))
            {
                status = IsStandard(v.Value, dbSource, false, v.Key) ? ItemStatus.AlreadyExists : ItemStatus.RequiresUpdate;
            }
            else
            {
                status = ItemStatus.Error; // Missing
            }
            
            results.Add(new("VIEW", v.Key, status));
        }

        // Custom columns
        foreach (var (table, column, _) in RequiredColumns)
        {
            var exists = await ColumnExistsAsync(conn, table, column);
            results.Add(new("COLUMN", $"{table}.{column}",
                exists ? ItemStatus.AlreadyExists : ItemStatus.Error));
        }

        // Generator PEDIDOS
        var genExists = await QuerySetAsync(conn,
            "SELECT TRIM(RDB$GENERATOR_NAME) FROM RDB$GENERATORS WHERE RDB$GENERATOR_NAME = 'PEDIDOS'");
        results.Add(new("GENERATOR", "PEDIDOS",
            genExists.Contains("PEDIDOS") ? ItemStatus.AlreadyExists : ItemStatus.Error));

        // Tabela COLISEU_SYNC_LOG
        var tableExists = await TableExistsAsync(conn, "COLISEU_SYNC_LOG");
        results.Add(new("TABLE", "COLISEU_SYNC_LOG",
            tableExists ? ItemStatus.AlreadyExists : ItemStatus.Error));

        // Index IDX_COLISEU_SYNC_LOG_TAB
        var indexExists = await QuerySetAsync(conn,
            "SELECT TRIM(RDB$INDEX_NAME) FROM RDB$INDICES WHERE RDB$INDEX_NAME = 'IDX_COLISEU_SYNC_LOG_TAB'");
        results.Add(new("INDEX", "IDX_COLISEU_SYNC_LOG_TAB",
            indexExists.Contains("IDX_COLISEU_SYNC_LOG_TAB") ? ItemStatus.AlreadyExists : ItemStatus.Error));

        // Generator GEN_COLISEU_SYNC_LOG
        var syncGenExists = await QuerySetAsync(conn,
            "SELECT TRIM(RDB$GENERATOR_NAME) FROM RDB$GENERATORS WHERE RDB$GENERATOR_NAME = 'GEN_COLISEU_SYNC_LOG'");
        results.Add(new("GENERATOR", "GEN_COLISEU_SYNC_LOG",
            syncGenExists.Contains("GEN_COLISEU_SYNC_LOG") ? ItemStatus.AlreadyExists : ItemStatus.Error));

        // Triggers de Rastreamento de Alterações
        var existingTriggers = await QuerySetAsync(conn,
            "SELECT TRIM(RDB$TRIGGER_NAME) FROM RDB$TRIGGERS WHERE RDB$SYSTEM_FLAG = 0");
        foreach (var (table, pk) in TrackedTables)
        {
            if (!await TableExistsAsync(conn, table))
            {
                continue;
            }
            foreach (var op in new[] { "I", "U", "D" })
            {
                var tgName = $"TG_CSYNC_{table}_{op}";
                results.Add(new("TRIGGER", tgName,
                    existingTriggers.Contains(tgName) ? ItemStatus.AlreadyExists : ItemStatus.Error));
            }
        }

        return results;
    }

    /// <summary>
    /// Fase 2: Bootstrap — cria todos os objetos faltantes.
    /// Retorna lista atualizada com os resultados da criação.
    /// </summary>
    public async Task<List<BootstrapItem>> BootstrapAsync(IProgress<string>? progress = null)
    {
        var results = new List<BootstrapItem>();

        await using var conn = new FbConnection(_connectionString);
        await conn.OpenAsync();

        // 1. Colunas customizadas (devem existir antes das SPs/Views que as referenciam)
        foreach (var (table, column, ddl) in RequiredColumns)
        {
            var name = $"{table}.{column}";
            if (await ColumnExistsAsync(conn, table, column))
            {
                results.Add(new("COLUMN", name, ItemStatus.AlreadyExists));
                progress?.Report($"✅ {name} — já existe");
                continue;
            }
            try
            {
                await ExecuteNonQueryAsync(conn, ddl);
                results.Add(new("COLUMN", name, ItemStatus.Created));
                progress?.Report($"🔧 {name} — criada");
            }
            catch (Exception ex)
            {
                results.Add(new("COLUMN", name, ItemStatus.Error, ex.Message));
                progress?.Report($"❌ {name} — erro: {ex.Message}");
            }
        }

        // 2. Generator
        var genExists = await QuerySetAsync(conn,
            "SELECT TRIM(RDB$GENERATOR_NAME) FROM RDB$GENERATORS WHERE RDB$GENERATOR_NAME = 'PEDIDOS'");
        if (genExists.Contains("PEDIDOS"))
        {
            results.Add(new("GENERATOR", "PEDIDOS", ItemStatus.AlreadyExists));
            progress?.Report("✅ Generator PEDIDOS — já existe");
        }
        else
        {
            try
            {
                await ExecuteNonQueryAsync(conn, "CREATE GENERATOR PEDIDOS");
                results.Add(new("GENERATOR", "PEDIDOS", ItemStatus.Created));
                progress?.Report("🔧 Generator PEDIDOS — criado");
            }
            catch (Exception ex)
            {
                results.Add(new("GENERATOR", "PEDIDOS", ItemStatus.Error, ex.Message));
                progress?.Report($"❌ Generator PEDIDOS — erro: {ex.Message}");
            }
        }

        // 3. Views (devem ser criadas ANTES de SPs que referenciam views como MOB_LISTACLIENTES)
        var existingViewsSource = await QuerySourcesAsync(conn,
            "SELECT TRIM(RDB$RELATION_NAME), RDB$VIEW_SOURCE FROM RDB$RELATIONS WHERE RDB$VIEW_BLR IS NOT NULL AND RDB$SYSTEM_FLAG = 0");
        foreach (var v in RequiredViews)
        {
            var isStandard = existingViewsSource.TryGetValue(v.Key, out var dbSource) && IsStandard(v.Value, dbSource, false, v.Key);
            if (isStandard)
            {
                results.Add(new("VIEW", v.Key, ItemStatus.AlreadyExists));
                progress?.Report($"✅ View {v.Key} — já está no padrão");
                continue;
            }

            try
            {
                await ExecuteNonQueryAsync(conn, v.Value);
                if (existingViewsSource.ContainsKey(v.Key))
                {
                    results.Add(new("VIEW", v.Key, ItemStatus.RequiresUpdate));
                    progress?.Report($"🔧 View {v.Key} — corrigida (estava fora do padrão)");
                }
                else
                {
                    results.Add(new("VIEW", v.Key, ItemStatus.Created));
                    progress?.Report($"🔧 View {v.Key} — criada");
                }
            }
            catch (Exception ex)
            {
                results.Add(new("VIEW", v.Key, ItemStatus.Error, ex.Message));
                progress?.Report($"❌ View {v.Key} — erro: {ex.Message}");
            }
        }

        // 4. Stored Procedures
        var existingProcsSource = await QuerySourcesAsync(conn,
            "SELECT TRIM(RDB$PROCEDURE_NAME), RDB$PROCEDURE_SOURCE FROM RDB$PROCEDURES WHERE RDB$SYSTEM_FLAG = 0");
            
        foreach (var sp in RequiredProcedures)
        {
            var isStandard = existingProcsSource.TryGetValue(sp.Key, out var dbSource) && IsStandard(sp.Value, dbSource, true, sp.Key);
            if (isStandard)
            {
                results.Add(new("SP", sp.Key, ItemStatus.AlreadyExists));
                progress?.Report($"✅ SP {sp.Key} — já está no padrão");
                continue;
            }

            try
            {
                await ExecuteNonQueryAsync(conn, sp.Value);
                if (existingProcsSource.ContainsKey(sp.Key))
                {
                    results.Add(new("SP", sp.Key, ItemStatus.RequiresUpdate));
                    progress?.Report($"🔧 SP {sp.Key} — corrigida (estava fora do padrão)");
                }
                else
                {
                    results.Add(new("SP", sp.Key, ItemStatus.Created));
                    progress?.Report($"🔧 SP {sp.Key} — criada");
                }
            }
            catch (Exception ex)
            {
                results.Add(new("SP", sp.Key, ItemStatus.Error, ex.Message));
                progress?.Report($"❌ SP {sp.Key} — erro: {ex.Message}");
            }
        }

        // 5. Tabela COLISEU_SYNC_LOG
        if (await TableExistsAsync(conn, "COLISEU_SYNC_LOG"))
        {
            results.Add(new("TABLE", "COLISEU_SYNC_LOG", ItemStatus.AlreadyExists));
            progress?.Report("✅ Tabela COLISEU_SYNC_LOG — já existe");
        }
        else
        {
            try
            {
                var ddl = @"
                    CREATE TABLE COLISEU_SYNC_LOG (
                        ID_LOG INTEGER NOT NULL,
                        NOME_TABELA VARCHAR(50) NOT NULL,
                        ID_REGISTRO VARCHAR(50) NOT NULL,
                        OPERACAO CHAR(1) NOT NULL,
                        DATA_HORA TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
                        CONSTRAINT PK_COLISEU_SYNC_LOG PRIMARY KEY (ID_LOG)
                    )";
                await ExecuteNonQueryAsync(conn, ddl);
                results.Add(new("TABLE", "COLISEU_SYNC_LOG", ItemStatus.Created));
                progress?.Report("🔧 Tabela COLISEU_SYNC_LOG — criada");
            }
            catch (Exception ex)
            {
                results.Add(new("TABLE", "COLISEU_SYNC_LOG", ItemStatus.Error, ex.Message));
                progress?.Report($"❌ Tabela COLISEU_SYNC_LOG — erro: {ex.Message}");
            }
        }

        // 6. Index IDX_COLISEU_SYNC_LOG_TAB
        var indices = await QuerySetAsync(conn, "SELECT TRIM(RDB$INDEX_NAME) FROM RDB$INDICES WHERE RDB$INDEX_NAME = 'IDX_COLISEU_SYNC_LOG_TAB'");
        if (indices.Contains("IDX_COLISEU_SYNC_LOG_TAB"))
        {
            results.Add(new("INDEX", "IDX_COLISEU_SYNC_LOG_TAB", ItemStatus.AlreadyExists));
            progress?.Report("✅ Index IDX_COLISEU_SYNC_LOG_TAB — já existe");
        }
        else
        {
            try
            {
                await ExecuteNonQueryAsync(conn, "CREATE INDEX IDX_COLISEU_SYNC_LOG_TAB ON COLISEU_SYNC_LOG (NOME_TABELA, ID_LOG)");
                results.Add(new("INDEX", "IDX_COLISEU_SYNC_LOG_TAB", ItemStatus.Created));
                progress?.Report("🔧 Index IDX_COLISEU_SYNC_LOG_TAB — criado");
            }
            catch (Exception ex)
            {
                results.Add(new("INDEX", "IDX_COLISEU_SYNC_LOG_TAB", ItemStatus.Error, ex.Message));
                progress?.Report($"❌ Index IDX_COLISEU_SYNC_LOG_TAB — erro: {ex.Message}");
            }
        }

        // 7. Generator GEN_COLISEU_SYNC_LOG
        var syncGens = await QuerySetAsync(conn, "SELECT TRIM(RDB$GENERATOR_NAME) FROM RDB$GENERATORS WHERE RDB$GENERATOR_NAME = 'GEN_COLISEU_SYNC_LOG'");
        if (syncGens.Contains("GEN_COLISEU_SYNC_LOG"))
        {
            results.Add(new("GENERATOR", "GEN_COLISEU_SYNC_LOG", ItemStatus.AlreadyExists));
            progress?.Report("✅ Generator GEN_COLISEU_SYNC_LOG — já existe");
        }
        else
        {
            try
            {
                await ExecuteNonQueryAsync(conn, "CREATE GENERATOR GEN_COLISEU_SYNC_LOG");
                results.Add(new("GENERATOR", "GEN_COLISEU_SYNC_LOG", ItemStatus.Created));
                progress?.Report("🔧 Generator GEN_COLISEU_SYNC_LOG — criado");
            }
            catch (Exception ex)
            {
                results.Add(new("GENERATOR", "GEN_COLISEU_SYNC_LOG", ItemStatus.Error, ex.Message));
                progress?.Report($"❌ Generator GEN_COLISEU_SYNC_LOG — erro: {ex.Message}");
            }
        }

        // 8. Triggers
        var existingTriggers = await QuerySetAsync(conn, "SELECT TRIM(RDB$TRIGGER_NAME) FROM RDB$TRIGGERS WHERE RDB$SYSTEM_FLAG = 0");
        foreach (var (table, pk) in TrackedTables)
        {
            if (!await TableExistsAsync(conn, table))
            {
                progress?.Report($"ℹ Tabela {table} não existe no banco de dados. Pulando triggers.");
                continue;
            }
            foreach (var op in new[] { ("I", "INSERT"), ("U", "UPDATE"), ("D", "DELETE") })
            {
                var tgName = $"TG_CSYNC_{table}_{op.Item1}";
                if (existingTriggers.Contains(tgName))
                {
                    results.Add(new("TRIGGER", tgName, ItemStatus.AlreadyExists));
                    progress?.Report($"✅ Trigger {tgName} — já existe");
                    continue;
                }

                try
                {
                    var prefix = op.Item1 == "D" ? "OLD" : "NEW";
                    var logTable = table;
                    if (table == "PEDIDO_ITENS") logTable = "PEDIDOS";
                    else if (table == "PRODUTO_DEPTOS" || table == "PRODUTO_PRECOS") logTable = "PRODUTOS";
                    var ddl = $@"
                        CREATE TRIGGER {tgName} FOR {table}
                        ACTIVE AFTER {op.Item2} POSITION 100
                        AS
                        BEGIN
                            INSERT INTO COLISEU_SYNC_LOG (ID_LOG, NOME_TABELA, ID_REGISTRO, OPERACAO)
                            VALUES (GEN_ID(GEN_COLISEU_SYNC_LOG, 1), '{logTable}', {prefix}.{pk}, '{op.Item1}');
                        END";
                    await ExecuteNonQueryAsync(conn, ddl);
                    results.Add(new("TRIGGER", tgName, ItemStatus.Created));
                    progress?.Report($"🔧 Trigger {tgName} — criada");
                }
                catch (Exception ex)
                {
                    results.Add(new("TRIGGER", tgName, ItemStatus.Error, ex.Message));
                    progress?.Report($"❌ Trigger {tgName} — erro: {ex.Message}");
                }
            }
        }

        return results;
    }

    // ── Helpers ─────────────────────────────────────────────────────────────

    private static async Task<HashSet<string>> QuerySetAsync(FbConnection conn, string sql)
    {
        var set = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        await using var tx = await conn.BeginTransactionAsync();
        await using var cmd = new FbCommand(sql, conn, tx);
        await using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            var val = reader.GetString(0).Trim();
            set.Add(val);
        }
        await tx.CommitAsync();
        return set;
    }

    private static async Task<bool> ColumnExistsAsync(FbConnection conn, string table, string column)
    {
        await using var tx = await conn.BeginTransactionAsync();
        await using var cmd = new FbCommand(
            "SELECT 1 FROM RDB$RELATION_FIELDS WHERE RDB$RELATION_NAME = @T AND TRIM(RDB$FIELD_NAME) = @C",
            conn, tx);
        cmd.Parameters.AddWithValue("@T", table);
        cmd.Parameters.AddWithValue("@C", column);
        var result = await cmd.ExecuteScalarAsync();
        await tx.CommitAsync();
        return result != null;
    }

    private static async Task ExecuteNonQueryAsync(FbConnection conn, string sql)
    {
        await using var tx = await conn.BeginTransactionAsync();
        await using var cmd = new FbCommand(sql, conn, tx);
        cmd.CommandTimeout = 30;
        await cmd.ExecuteNonQueryAsync();
        await tx.CommitAsync();
    }

    private static async Task<Dictionary<string, string>> QuerySourcesAsync(FbConnection conn, string sql)
    {
        var dict = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        await using var tx = await conn.BeginTransactionAsync();
        await using var cmd = new FbCommand(sql, conn, tx);
        await using var reader = await cmd.ExecuteReaderAsync();
        while (await reader.ReadAsync())
        {
            var name = reader.GetString(0).Trim();
            var source = reader.IsDBNull(1) ? string.Empty : reader.GetString(1);
            dict[name] = NormalizeSource(source);
        }
        await tx.CommitAsync();
        return dict;
    }

    private static string NormalizeSource(string? source)
    {
        if (string.IsNullOrWhiteSpace(source)) return string.Empty;
        var noComments = System.Text.RegularExpressions.Regex.Replace(source, @"--.*(\r?\n|$)", " ");
        var asciiOnly = System.Text.RegularExpressions.Regex.Replace(noComments, @"[^\x20-\x7E]|\?", " ");
        return System.Text.RegularExpressions.Regex.Replace(asciiOnly.ToUpperInvariant(), @"\s+", " ").Trim();
    }

    private static bool IsStandard(string expectedDdl, string dbSourceNormalized, bool isProcedure, string name)
    {
        if (string.IsNullOrWhiteSpace(dbSourceNormalized)) return false;
        
        string expectedBody;
        if (isProcedure)
        {
            var regex = new System.Text.RegularExpressions.Regex($@"CREATE\s+(?:OR\s+ALTER\s+)?PROCEDURE\s+{name}\s*(?:\(.*?\))?\s*AS\s*", System.Text.RegularExpressions.RegexOptions.IgnoreCase | System.Text.RegularExpressions.RegexOptions.Singleline);
            expectedBody = regex.Replace(expectedDdl, "", 1); // remove the header
        }
        else
        {
            var regex = new System.Text.RegularExpressions.Regex($@"(?:CREATE\s+(?:OR\s+ALTER\s+)?|RECREATE\s+)VIEW\s+{name}\s*(?:\(.*?\))?\s*AS\s*", System.Text.RegularExpressions.RegexOptions.IgnoreCase | System.Text.RegularExpressions.RegexOptions.Singleline);
            expectedBody = regex.Replace(expectedDdl, "", 1); // remove the header
        }

        var expectedNormalized = NormalizeSource(expectedBody);
        return expectedNormalized == dbSourceNormalized;
    }

    // ════════════════════════════════════════════════════════════════════════
    // DDL DEFINITIONS — Extraídas do banco Firebird de produção (PIVETA.FDB)
    // ════════════════════════════════════════════════════════════════════════

    // ── Colunas customizadas ───────────────────────────────────────────────

    private static readonly (string Table, string Column, string Ddl)[] RequiredColumns =
    {
        ("FUNCIONARIOS", "MOB_ACESSO",   "ALTER TABLE FUNCIONARIOS ADD MOB_ACESSO SMALLINT DEFAULT 0"),
        ("FUNCIONARIOS", "MOB_SENHA",    "ALTER TABLE FUNCIONARIOS ADD MOB_SENHA VARCHAR(6)"),
        ("FUNCIONARIOS", "ID_MOBILE",    "ALTER TABLE FUNCIONARIOS ADD ID_MOBILE INTEGER"),
        ("FUNCIONARIOS", "DESCONTO_MAX", "ALTER TABLE FUNCIONARIOS ADD DESCONTO_MAX FLOAT DEFAULT 0"),
        ("FUNCIONARIOS", "COMISSAO",     "ALTER TABLE FUNCIONARIOS ADD COMISSAO FLOAT DEFAULT 0"),
        ("ESPECIE_PGTO", "MOB_ACESSO",  "ALTER TABLE ESPECIE_PGTO ADD MOB_ACESSO SMALLINT DEFAULT 0"),
        ("FORMA_PGTO",   "MOB_ACESSO",  "ALTER TABLE FORMA_PGTO ADD MOB_ACESSO SMALLINT DEFAULT 0"),
        ("NATUREZA_OPERACAO", "MOB_ACESSO", "ALTER TABLE NATUREZA_OPERACAO ADD MOB_ACESSO SMALLINT DEFAULT 0"),
        ("NATUREZA_OPERACAO", "MOB_ORDEM",  "ALTER TABLE NATUREZA_OPERACAO ADD MOB_ORDEM SMALLINT DEFAULT 0"),
        ("ADM_GLOBAL",   "NR_MOB",      "ALTER TABLE ADM_GLOBAL ADD NR_MOB INTEGER DEFAULT 0"),
    };

    // ── Stored Procedures ──────────────────────────────────────────────────

    private static readonly Dictionary<string, string> RequiredProcedures = new()
    {
        ["MOB_CADASTRAR_PEDIDO"] = """
            CREATE OR ALTER PROCEDURE MOB_CADASTRAR_PEDIDO (
                USUARIO integer,
                CLIENTE integer,
                DATA timestamp,
                HORA timestamp,
                OBSERVACAO varchar(50),
                PRAZO_PEDIDO varchar(20),
                TIPO_OPERACAO varchar(20),
                PAGAMENTO integer,
                VALOR_DESCONTO numeric(15,2),
                TOTAL_PEDIDO numeric(15,2),
                CONDICAO_PAGAMENTO integer,
                DEPTO integer,
                EMPRESA integer)
            AS
            declare variable CD_NP integer;
            declare variable CD_PD integer;
            declare variable CD_NPI integer;
            declare variable CD_NTP integer;
            declare variable CD_DPP integer;
            declare variable CD_MOB integer;
            declare variable PEMPRESA integer;
            declare variable OP_DI smallint;
            BEGIN
                PEMPRESA = :EMPRESA;

                SELECT GEN_ID(PEDIDOS,1) FROM RDB$DATABASE INTO :CD_NP;

                SELECT MAX(NR_PED) FROM ADM_SEQUENCIA WHERE ID_EMPRESA = :PEMPRESA INTO :CD_PD;

                SELECT DESCONTO_ITEM FROM CONFIG WHERE ID_EMPRESA = :PEMPRESA INTO :OP_DI;

                IF (CD_PD IS NULL) THEN
                    CD_PD = 1;
                    ELSE
                    CD_PD = CD_PD + 1;

                SELECT COALESCE(NR_MOB,0) FROM ADM_GLOBAL INTO :CD_MOB;

                CD_MOB = (CD_MOB + 1);

                UPDATE ADM_GLOBAL SET NR_MOB = :CD_MOB;

                INSERT INTO PEDIDOS (ID_PEDIDO, ID_MOBILE, PEDIDO, ID_CLIENTE, ID_ESPECIE, DATA_HORA, ID_FUNCIONARIO, ID_VENDEDOR,
                        VALOR_PEDIDO, ID_NATUREZA, AJUSTE, TIPO, STATUS, ID_DEPTO, ID_PORTADOR, NOTA_FISCAL, CUPOM_FISCAL,
                        BASE_CALCULO, VALOR_ICMS, BASE_ICMS_SUB, VALOR_ICMS_SUB, DESCONTO, VALOR_SERVICOS, VALOR_CUSTOS, VALOR_BASE,
                        VALOR_ENTRADA, ITENS, QTDE_TOTAL, ID_FORMA, VALOR_FRETE, TIPO_FRETE, TIPO_TRANSPORTE,
                        N_NOTA, OUTRAS_DESPESAS, VALOR_IPI, NF, TIPO_PO, TIPO_A_PRECO, DEVOLUCAO, ENTREGA, TIPO_NOTA, TIPO_EMISSAO, 
                        ACRESCIMO, PESO_TOTAL, OBS,STATUS_ENTREGA)
                VALUES ( :CD_NP, 1, 'MOB'||:CD_MOB, :CLIENTE, :PAGAMENTO, CURRENT_TIMESTAMP, :USUARIO, :USUARIO,
                (:TOTAL_PEDIDO+:VALOR_DESCONTO),:TIPO_OPERACAO,0, 1, 0,
                :DEPTO,
                (SELECT PORTADOR_PADRAO FROM CONFIG WHERE ID_EMPRESA = :PEMPRESA),
                '0', '0',0, 0, 0, 0,((:VALOR_DESCONTO*100)/ ( 
                CASE WHEN 
                    (:TOTAL_PEDIDO+:VALOR_DESCONTO) = 0 THEN 1 
                ELSE (:TOTAL_PEDIDO+:VALOR_DESCONTO)END )), 0, 0, 0, 0, 0, 0, 
                :CONDICAO_PAGAMENTO, 0, 2, 1,0, 0, 0, 2, 1, 0, 0, 0, 1, 0, 0, 0, :OBSERVACAO,1);

                EXECUTE STATEMENT 'SET GENERATOR PEDIDOS TO ' || :CD_NP;
            END
            """,
        ["MOB_CADASTRAR_PEDIDO_ITEM"] = """
            CREATE OR ALTER PROCEDURE MOB_CADASTRAR_PEDIDO_ITEM (
                ID_PEDIDO INTEGER,
                PRODUTO INTEGER,
                QUANTIDADE FLOAT,
                OBSERVACAO VARCHAR(50),
                VALOR_UNITARIO NUMERIC(18,2),
                VALOR_DESCONTO NUMERIC(18,2),
                VALOR_TOTAL NUMERIC(18,2)
            )
            AS
            declare variable ITEM integer;
            begin
                select coalesce(max(id_item),0)+1 from PEDIDO_ITENS where id_pedido = :ID_PEDIDO into :ITEM;
                insert into PEDIDO_ITENS (ID_PEDIDO, ID_ITEM, ID_PRODUTO, DESCRICAO, UNIDADE, QTDE, VALOR_UNITARIO, CF, VALOR_TOTAL, VALOR_FINAL, VALOR_FINAL_UN,
                                          TIPO, VALOR_CUSTO, CODIGO_BARRA, TIPO_UNIDADE, DESCONTO, STATUS, ICMS, REDUCAO_ICMS, TRIBUTACAO,
                                          BASE_CALCULO, VALOR_ICMS, BASE_ICMS_SUB, VALOR_ICMS_SUB, PESO, CFOP, PIS_CST, COFINS_CST, IPI_CST, PIS, COFINS, IPI, CSOSN,
                                          ORIGEM, LUCRO, LUCRO_MAX, ENTREGAR, VALOR_IPI, BASE_IPI, BASE_PIS, BASE_COFINS)
                                          values ( :ID_PEDIDO, :ITEM, :PRODUTO,
                                          (select descricao from produtos where ID_PRODUTO = :PRODUTO),
                                          (select unidade from produtos where ID_PRODUTO = :PRODUTO),
                                          :QUANTIDADE, :VALOR_UNITARIO,
                                          (select ORIGEM_MERCADORIA || TRIBUTACAO from produtos where ID_PRODUTO = :PRODUTO),
                                          :VALOR_TOTAL, :VALOR_TOTAL, :VALOR_UNITARIO, 1,
                                          (select PRODUTO_PRECOS.PRECO_CUSTO from produtos, produto_precos where (produtos.id_produto = produto_precos.id_produto) and (produto_precos.ativo = 1) and (produtos.ID_PRODUTO = :PRODUTO)),
                                          (select codigo_barra from produtos where ID_PRODUTO = :PRODUTO), 1,
                                          (select desconto from pedidos where id_pedido = :ID_PEDIDO), 1,
                                          (select icms from produtos where ID_PRODUTO = :PRODUTO),
                                          (select reducao from produtos where ID_PRODUTO = :PRODUTO),
                                          (select tributacao from produtos where ID_PRODUTO = :PRODUTO),
                                          0, 0, 0, 0,
                                          (select peso from produtos where ID_PRODUTO = :PRODUTO), (select cfop_e from produtos where ID_PRODUTO = :PRODUTO),
                                          (select pis_cst from produtos where ID_PRODUTO = :PRODUTO),
                                          (select cofins_cst from produtos where ID_PRODUTO = :PRODUTO),
                                          (select ipi_cst from produtos where ID_PRODUTO = :PRODUTO),
                                          (select pis from produtos where ID_PRODUTO = :PRODUTO),
                                          (select cofins from produtos where ID_PRODUTO = :PRODUTO),
                                          (select ipi from produtos where ID_PRODUTO = :PRODUTO),
                                          (select csosn from produtos where ID_PRODUTO = :PRODUTO),
                                          (select origem_mercadoria from produtos where ID_PRODUTO = :PRODUTO),
                                          (select margem_lucro from produtos where ID_PRODUTO = :PRODUTO),
                                          (select margem_maxima from produtos where ID_PRODUTO = :PRODUTO), 0,
                                          0, 0, 0, 0);
                update PEDIDOS set
                peso_total = (select sum(peso) from pedido_itens where id_pedido = :ID_PEDIDO)
                where id_pedido = :ID_PEDIDO;
            end
            """,

        ["MOB_CADASTRA_CLIENTE"] = """
            CREATE OR ALTER PROCEDURE MOB_CADASTRA_CLIENTE (
                TIPOPESSOA VARCHAR(15),
                NOME VARCHAR(70),
                CPFCNPJ VARCHAR(20),
                EMAIL VARCHAR(50),
                TELEFONE VARCHAR(18),
                CEP VARCHAR(9),
                CIDADE VARCHAR(50),
                UF VARCHAR(2),
                ENDERECO VARCHAR(50),
                NUMERO VARCHAR(10),
                BAIRRO VARCHAR(30),
                IDUSUARIO INTEGER,
                TABELAPRECO INTEGER,
                COMPLEMENTO VARCHAR(30),
                INSCRICAOESTADUAL VARCHAR(18)
            )
            AS
            declare variable IDCLI integer;
            declare variable IDREG integer;
            begin
                select (cast(gen_id(CLIENTES,0) as integer)+1) from RDB$DATABASE into :IDCLI;
                select FIRST 1 coalesce(id_regiao,0) from REGIOES where CIDADE = :CIDADE and UF = :UF into :IDREG;
                insert into CLIENTES (ID_CLIENTE, CPF_CNPJ, IE, NOME, NOME_FANTASIA, PESSOA, TIPO, CLASSIFICACAO, ID_REGIAO, ID_CLASSE, SUBSTITUTO, SALDO, LIMITE, DATA_CADASTRO, DATA_UP, USER_IN, EMAIL)
                VALUES (:IDCLI, :CPFCNPJ, :INSCRICAOESTADUAL, :NOME, SUBSTRING(:NOME FROM 1 FOR 50), CASE WHEN :TIPOPESSOA = 'Pessoa Juridica' THEN 2 ELSE 1 END, 1, 0, :IDREG, 0, 0, 0, 0, current_date, current_timestamp, :IDUSUARIO, :EMAIL);
                insert into CLIENTES_DADOS (ID_CLIENTE, ENDERECO, NUMERO, BAIRRO, COMPLEMENTO, FONE_RES, CEP, TIPO_ENDERECO)
                VALUES (:IDCLI, :ENDERECO, :NUMERO, :BAIRRO, :COMPLEMENTO, :TELEFONE, :CEP, 1);
                execute statement 'SET GENERATOR CLIENTES TO ' || IDCLI;
            end
            """,

        ["MINHASVENDAS"] = """
            CREATE OR ALTER PROCEDURE MINHASVENDAS (
                VENDEDOR INTEGER,
                MES SMALLINT,
                ANO SMALLINT,
                DATA DATE
            )
            RETURNS (
                VENDA_DIARIA NUMERIC(18,2),
                VENDA_MENSAL NUMERIC(18,2),
                COMISSAO_DIARIA NUMERIC(18,2),
                COMISSAO_MENSAL NUMERIC(18,2),
                META_DIARIA NUMERIC(18,2),
                META_MENSAL NUMERIC(18,2),
                SERVICO_MENSAL NUMERIC(18,2),
                COMISSAO_SV_MENSAL NUMERIC(18,2)
            )
            AS
            declare variable MT_D numeric(15,2);
            declare variable MT_M numeric(15,2);
            declare variable VEND_D numeric(15,2);
            declare variable VEND_M numeric(15,2);
            declare variable COM_D numeric(15,2);
            declare variable COM_M numeric(15,2);
            declare variable SERV_M numeric(15,2);
            declare variable COM_SV_M numeric(15,2);
            begin
            select FUNCIONARIOS.META_DIARIA, FUNCIONARIOS.META_MENSAL,
            sum((case when ((ESTOQUE.es = 1) or (ESTOQUE.tipo = 3)) then ESTOQUE.valor_total when ((ESTOQUE.es = 2) and (NATUREZA_OPERACAO.processo = 2)) then (ESTOQUE.valor_total*-1) end) - (((case when ((ESTOQUE.es = 1) or (ESTOQUE.tipo = 3)) then ESTOQUE.valor_total when ((ESTOQUE.es = 2) and (NATUREZA_OPERACAO.processo = 2)) then (ESTOQUE.valor_total*-1) end)*PEDIDOS.desconto)/100)),
            sum((case when ((ESTOQUE.es = 1) or (ESTOQUE.tipo = 3)) then ESTOQUE.valor_comissao when ((ESTOQUE.es = 2) and (NATUREZA_OPERACAO.processo = 2)) then (ESTOQUE.valor_comissao*-1) end))
            from ESTOQUE
            inner join PEDIDOS on (PEDIDOS.ID_PEDIDO = ESTOQUE.ID_PEDIDO)
            left join FUNCIONARIOS on (FUNCIONARIOS.ID_FUNCIONARIO = PEDIDOS.id_vendedor)
            left join natureza_operacao on (natureza_operacao.id_natureza = pedidos.id_natureza)
            where (natureza_operacao.calc_comissao = 1)
            and (extract(month from PEDIDOS.data_vencimento) = :MES)
            and (extract(year from PEDIDOS.data_vencimento) = :ANO)
            and (PEDIDOS.ID_VENDEDOR = :VENDEDOR)
            and (PEDIDOS.TIPO = 1) and (PEDIDOS.STATUS = 2)
            and (ESTOQUE.STATUS <> 9) and (ESTOQUE.movc = 1)
            group by FUNCIONARIOS.META_DIARIA, FUNCIONARIOS.META_MENSAL
            into :MT_D, :MT_M, :VEND_M, :COM_M;
            select
            sum((case when ((ESTOQUE.es = 1) or (ESTOQUE.tipo = 3)) then ESTOQUE.valor_total when ((ESTOQUE.es = 2) and (NATUREZA_OPERACAO.processo = 2)) then (ESTOQUE.valor_total*-1) end) - (((case when ((ESTOQUE.es = 1) or (ESTOQUE.tipo = 3)) then ESTOQUE.valor_total when ((ESTOQUE.es = 2) and (NATUREZA_OPERACAO.processo = 2)) then (ESTOQUE.valor_total*-1) end)*PEDIDOS.desconto)/100)),
            sum((case when ((ESTOQUE.es = 1) or (ESTOQUE.tipo = 3)) then ESTOQUE.valor_comissao when ((ESTOQUE.es = 2) and (NATUREZA_OPERACAO.processo = 2)) then (ESTOQUE.valor_comissao*-1) end))
            from ESTOQUE
            inner join PEDIDOS on (PEDIDOS.ID_PEDIDO = ESTOQUE.ID_PEDIDO)
            left join FUNCIONARIOS on (FUNCIONARIOS.ID_FUNCIONARIO = PEDIDOS.id_vendedor)
            left join natureza_operacao on (natureza_operacao.id_natureza = pedidos.id_natureza)
            where (natureza_operacao.calc_comissao = 1) and ((PEDIDOS.data_vencimento >= :DATA) and (PEDIDOS.data_vencimento <= :DATA))
            and (PEDIDOS.ID_VENDEDOR = :VENDEDOR)
            and (PEDIDOS.TIPO = 1) and (PEDIDOS.STATUS = 2)
            and (ESTOQUE.STATUS <> 9) and (ESTOQUE.movc = 1)
            into :VEND_D, :COM_D;
            select sum(LISTAPEDIDOS_ITENS.VALOR_TOTAL),
            sum(((LISTAPEDIDOS_ITENS.VALOR_TOTAL*(case when PRODUTOS.forca_comissao = 1 then PRODUTOS.comissao else FUNCIONARIOS.comissao end))/100))
            from LISTAPEDIDOS_ITENS
            left join PRODUTOS on (PRODUTOS.ID_PRODUTO = LISTAPEDIDOS_ITENS.ID_PRODUTO)
            left join CLIENTES on (CLIENTES.ID_CLIENTE = LISTAPEDIDOS_ITENS.ID_CLIENTE)
            left join CLIENTES_VEICULOS on (CLIENTES_VEICULOS.ID_VEICULO = LISTAPEDIDOS_ITENS.ID_VEICULO)
            left join REGIOES on (REGIOES.ID_REGIAO = CLIENTES.id_regiao)
            left join FUNCIONARIOS on (FUNCIONARIOS.ID_FUNCIONARIO = LISTAPEDIDOS_ITENS.id_tecnico)
            left join NATUREZA_OPERACAO on (natureza_operacao.id_natureza = LISTAPEDIDOS_ITENS.id_natureza)
            where (natureza_operacao.calc_comissao = 1) and ((LISTAPEDIDOS_ITENS.tipo_item = 3) or (LISTAPEDIDOS_ITENS.tipo_item = 6))
            and (extract(month from LISTAPEDIDOS_ITENS.data_vencimento) = :MES)
            and (extract(year from LISTAPEDIDOS_ITENS.data_vencimento) = :ANO)
            and (LISTAPEDIDOS_ITENS.id_tecnico = :VENDEDOR)
            and (LISTAPEDIDOS_ITENS.TIPO = 1) and (LISTAPEDIDOS_ITENS.STATUS = 2)
            into :SERV_M, :COM_SV_M;
            if (VEND_D is null) then VEND_D = 0;
            if (VEND_M is null) then VEND_M = 0;
            if (COM_D is null) then COM_D = 0;
            if (COM_M is null) then COM_M = 0;
            if (MT_D is null) then MT_D = 0;
            if (MT_M is null) then MT_M = 0;
            if (SERV_M is null) then SERV_M = 0;
            if (COM_SV_M is null) then COM_SV_M = 0;
            VENDA_DIARIA = VEND_D;
            VENDA_MENSAL = VEND_M;
            COMISSAO_DIARIA = COM_D;
            COMISSAO_MENSAL = COM_M;
            META_DIARIA = MT_D;
            META_MENSAL = MT_M;
            SERVICO_MENSAL = SERV_M;
            COMISSAO_SV_MENSAL = COM_SV_M;
            end
            """,

        ["MINHASVENDASR"] = """
            CREATE OR ALTER PROCEDURE MINHASVENDASR (
                VENDEDOR INTEGER,
                DATAI DATE,
                DATAF DATE,
                DIA DATE,
                EMPRESA INTEGER
            )
            RETURNS (
                TOTAL_DIARIO NUMERIC(18,2),
                TOTAL_MENSAL NUMERIC(18,2),
                COMISSAO_DIARIA NUMERIC(18,2),
                COMISSAO_MENSAL NUMERIC(18,2)
            )
            AS
            declare variable COM_D decimal(15,2);
            declare variable COM_M decimal(15,2);
            declare variable TOT_V_D decimal(15,2);
            declare variable TOT_V_M decimal(15,2);
            declare variable TP_COM smallint;
            begin
            select COMISSAO_TIPO from config where ID_EMPRESA = :EMPRESA into :TP_COM;
            if (TP_COM = 1) Then
               BEGIN
                  Select SUM(VALOR_PAGO), SUM(COMISSAO_PAGAR) from REL_IC_COMISSAO2 WHERE ((DATA_PAGAMENTO >= :DATAI) AND (DATA_PAGAMENTO <= :DATAF)) AND (ID_VENDEDOR = :VENDEDOR) into :TOT_V_M, :COM_M;
                  Select SUM(VALOR_PAGO), SUM(COMISSAO_PAGAR) from REL_IC_COMISSAO2 WHERE (DATA_PAGAMENTO = :DIA) AND (ID_VENDEDOR = :VENDEDOR) into :TOT_V_D, :COM_D;
               END
            if (TP_COM = 2) Then
               BEGIN
                  Select SUM(VALOR_PAGO), SUM(COMISSAO_PAGAR) from REL_IC_COMISSAO_ITEM2 WHERE ((DATA_PAGAMENTO >= :DATAI) AND (DATA_PAGAMENTO <= :DATAF)) AND (ID_VENDEDOR = :VENDEDOR) into :TOT_V_M, :COM_M;
                  Select SUM(VALOR_PAGO), SUM(COMISSAO_PAGAR) from REL_IC_COMISSAO_ITEM2 WHERE (DATA_PAGAMENTO = :DIA) AND (ID_VENDEDOR = :VENDEDOR) into :TOT_V_D, :COM_D;
               END
            if (TP_COM = 3) Then
               BEGIN
                  Select SUM(VALOR_PAGO), SUM(COMISSAO_PAGAR) from REL_IC_COMISSAO_VAR2 WHERE ((DATA_PAGAMENTO >= :DATAI) AND (DATA_PAGAMENTO <= :DATAF)) AND (ID_VENDEDOR = :VENDEDOR) into :TOT_V_M, :COM_M;
                  Select SUM(VALOR_PAGO), SUM(COMISSAO_PAGAR) from REL_IC_COMISSAO_VAR2 WHERE (DATA_PAGAMENTO = :DIA) AND (ID_VENDEDOR = :VENDEDOR) into :TOT_V_D, :COM_D;
               END
            if (COM_D is null) then COM_D = 0;
            if (COM_M is null) then COM_M = 0;
            if (TOT_V_D is null) then TOT_V_D = 0;
            if (TOT_V_M is null) then TOT_V_M = 0;
            COMISSAO_DIARIA = COM_D;
            COMISSAO_MENSAL = COM_M;
            TOTAL_DIARIO = TOT_V_D;
            TOTAL_MENSAL = TOT_V_M;
            end
            """,
    };

    // ── Views ──────────────────────────────────────────────────────────────

    private static readonly Dictionary<string, string> RequiredViews = new()
    {
        ["MOB_LISTACLIENTES"] = """
            CREATE OR ALTER VIEW MOB_LISTACLIENTES AS
            select clientes.id_cliente, cast(clientes.nome as varchar(70)) as NOME, clientes.cpf_cnpj, clientes.rg, clientes.ie, clientes.im, clientes.saldo, regioes.cidade, regioes.distrito, regioes.uf, regioes.codigo_ibge,
            clientes_dados.cep, (clientes_dados.endereco || ', ' || clientes_dados.numero) as ENDERECO_FULL, clientes_dados.bairro, clientes_dados.complemento, clientes_dados.fone_res, clientes_dados.fone_com, clientes_dados.celular,
            clientes_dados.tipo_endereco, clientes.tipo, clientes.dia_vencimento, clientes.dias_antes, clientes.id_convenio, convenios.descricao as convenio, convenios.desconto, convenios.visualizacao,
            clientes.ultima_compra, cast(clientes.nome_fantasia as varchar(50)) as NOME_FANTASIA, clientes.classificacao, clientes.id_vendedor, clientes.id_tabela, clientes_dados.estado_civil, clientes.pessoa, clientes.limite, clientes.substituto, clientes.nascimento,
            clientes_dados.renda, clientes_dados.profissao, clientes.id_regiao, clientes.data_cadastro, clientes.email, clientes.user_in,
            CASE when (CLIENTES.classificacao = 0) then 'NAO DEFINIDO'
                   when (CLIENTES.classificacao = 1) then 'INATIVO'
                   when (CLIENTES.classificacao = 2) then 'RUIM'
                   when (CLIENTES.classificacao = 3) then 'REGULAR'
                   when (CLIENTES.classificacao = 4) then 'BOM'
                   when (CLIENTES.classificacao = 5) then 'OTIMO'
                   when (CLIENTES.classificacao = 6) then 'PREFERENCIAL'
                   when (CLIENTES.classificacao = 96) then 'PENDENTE'
                   when (CLIENTES.classificacao = 97) then 'EM COBRANCA'
                   when (CLIENTES.classificacao = 98) then 'INADIMPLENTE'
                   when (CLIENTES.classificacao = 99) then 'NEGATIVO'
                   END as CLASSIFICACAO_DESC
            from CLIENTES
            left join clientes_dados on (clientes_dados.id_cliente = clientes.id_cliente)
            left join regioes on (regioes.id_regiao = clientes.id_regiao)
            left join convenios on (convenios.id_convenio = clientes.id_convenio)
            left join classes on (classes.id_classe = clientes.id_classe)
            where (CLIENTES.CLASSIFICACAO <> 1) and (CLIENTES.tipo = 1)
            """,

        ["MOB_LISTACONTAS"] = """
            CREATE OR ALTER VIEW MOB_LISTACONTAS AS
            select CONTAS.ID_CONTA, (LPAD(EXTRACT(YEAR FROM CONTAS.data_vencimento), 4, '0') || '-' ||
                                     LPAD(EXTRACT(MONTH FROM CONTAS.data_vencimento), 2, '0') || '-' ||
                                     LPAD(EXTRACT(DAY FROM CONTAS.data_vencimento), 2, '0')) as DATA_VENCIMENTO_FMT,
            CONTAS.id_cliente, CONTAS.n_doc, CONTAS.baixa, CONTAS.tipo,
            CONTAS.dc,
            (case when contas.tipo = 3 then (contas.valor*-1) else contas.valor end) as VALOR_CALC,
            ((case when ((current_date-contas.data_vencimento) > 0) and ((current_date-contas.data_vencimento) < 10000) then (contas.valor * cast(( dpower( cast((1+(contas.juros_depois/100)) as float), cast((cast((current_date-contas.data_vencimento) as float)/30) as float) )) as float)) else contas.valor end)-contas.valor) as JUROS_CALC,
            CONTAS.id_especie,
            CONTAS.descricao as DESCRICAO,
            CASE when (CONTAS.BAIXA = 0) then 'EM ABERTO'
                 when (CONTAS.BAIXA = 0) AND (DATA_VENCIMENTO < CURRENT_DATE) then 'VENCIDA'
                 when (CONTAS.BAIXA = 1) then 'QUITADA'
                 when (CONTAS.BAIXA = 2) then 'PARCIAL'
                 when (CONTAS.BAIXA = 8) then 'RENEGOCIADA'
                 when (CONTAS.BAIXA = 9) then 'CANCELADA'
                 END as STATUS_TEXTO
            from CONTAS
            left join CLIENTES on (CLIENTES.ID_CLIENTE = CONTAS.ID_CLIENTE)
            left join CLIENTES_DADOS on (CLIENTES_DADOS.ID_CLIENTE = CLIENTES.ID_CLIENTE)
            left join REGIOES on (REGIOES.ID_REGIAO = CLIENTES.ID_REGIAO)
            left join ESPECIE_PGTO on (ESPECIE_PGTO.ID_ESPECIE = CONTAS.ID_ESPECIE)
            left join PORTADOR on (PORTADOR.ID_PORTADOR = CONTAS.ID_PORTADOR)
            left join MOEDAS on (MOEDAS.ID_MOEDA = CONTAS.ID_MOEDA)
            left join PLANO_CONTAS on (PLANO_CONTAS.ID_PLANO = CONTAS.ID_PLANO)
            where (CONTAS.BAIXA = 0)
            """,

        ["L_VENDAS_PRODUTO"] = """
            CREATE OR ALTER VIEW L_VENDAS_PRODUTO (
                ID_PEDIDO, TIPO, DATA_HORA, DATA_VENCIMENTO, PRODUTO, ID_PRODUTO, 
                QTDE, VALOR_PEDIDO, TIPO_FP, TIPO_EP, TIPO_NAT, TIPO_PS, ID_CLIENTE, 
                STATUS, NOTA_FISCAL, NOTA_FISCAL_SERV, CUPOM_FISCAL, NFCE_NUMERO, 
                ID_VENDEDOR, ID_DEPTO, ID_CLASSE, ID_REGIAO
            ) AS
            SELECT LISTAPEDIDOS_ITENS.id_pedido, LISTAPEDIDOS_ITENS.TIPO, LISTAPEDIDOS_ITENS.DATA_HORA, LISTAPEDIDOS_ITENS.DATA_VENCIMENTO, PRODUTOS.descricao, PRODUTOS.id_produto,
            SUM(LISTAPEDIDOS_ITENS.QTDE), SUM(LISTAPEDIDOS_ITENS.VALOR_TOTAL2),
            forma_pgto.tipo, especie_pgto.tipo, NATUREZA_OPERACAO.tipo, PRODUTOS.tipo, LISTAPEDIDOS_ITENS.ID_CLIENTE, LISTAPEDIDOS_ITENS.STATUS, LISTAPEDIDOS_ITENS.NOTA_FISCAL, LISTAPEDIDOS_ITENS.NOTA_FISCAL_SERV, LISTAPEDIDOS_ITENS.CUPOM_FISCAL, LISTAPEDIDOS_ITENS.NFCE_NUMERO, LISTAPEDIDOS_ITENS.ID_VENDEDOR, LISTAPEDIDOS_ITENS.ID_DEPTO,
            CLIENTES.id_classe, CLIENTES.id_regiao
            FROM LISTAPEDIDOS_ITENS
            LEFT JOIN produtos ON (produtos.id_produto = listapedidos_itens.id_produto)
            LEFT JOIN categorias ON (categorias.id_categoria = produtos.id_categoria)
            LEFT JOIN natureza_operacao ON (natureza_operacao.id_natureza = listapedidos_itens.id_natureza)
            LEFT JOIN clientes ON (clientes.id_cliente = listapedidos_itens.id_cliente)
            LEFT JOIN especie_pgto ON (especie_pgto.id_especie = listapedidos_itens.id_especie)
            LEFT JOIN forma_pgto ON (forma_pgto.id_forma = listapedidos_itens.id_forma)
            WHERE (LISTAPEDIDOS_ITENS.STATUS = 2) AND ((LISTAPEDIDOS_ITENS.OPERACAO = 1) or (LISTAPEDIDOS_ITENS.OPERACAO = 6) or (LISTAPEDIDOS_ITENS.OPERACAO = 12))
            AND (natureza_operacao.tipo <> 2) AND (natureza_operacao.processo <> 3)
            GROUP BY LISTAPEDIDOS_ITENS.ID_PEDIDO, LISTAPEDIDOS_ITENS.TIPO, LISTAPEDIDOS_ITENS.DATA_HORA, LISTAPEDIDOS_ITENS.DATA_VENCIMENTO, PRODUTOS.descricao, PRODUTOS.id_produto, forma_pgto.tipo, especie_pgto.tipo, NATUREZA_OPERACAO.tipo, PRODUTOS.tipo, LISTAPEDIDOS_ITENS.ID_CLIENTE, LISTAPEDIDOS_ITENS.STATUS, LISTAPEDIDOS_ITENS.NOTA_FISCAL, LISTAPEDIDOS_ITENS.NOTA_FISCAL_SERV, LISTAPEDIDOS_ITENS.CUPOM_FISCAL, LISTAPEDIDOS_ITENS.NFCE_NUMERO, LISTAPEDIDOS_ITENS.ID_VENDEDOR, LISTAPEDIDOS_ITENS.ID_DEPTO, CLIENTES.id_classe, CLIENTES.id_regiao
            """,

        ["L_VENDAS_CLIENTE"] = """
            CREATE OR ALTER VIEW L_VENDAS_CLIENTE (
                ID_PEDIDO, TIPO, DATA_HORA, DATA_VENCIMENTO, CLIENTE, VALOR_PEDIDO, 
                TIPO_FP, TIPO_EP, TIPO_NAT, ID_CLIENTE, STATUS, NOTA_FISCAL, NOTA_FISCAL_SERV, 
                CUPOM_FISCAL, NFCE_NUMERO, ID_VENDEDOR, ID_DEPTO, ID_CLASSE, ID_REGIAO
            ) AS
            SELECT LISTAPEDIDOS.ID_PEDIDO, LISTAPEDIDOS.TIPO, LISTAPEDIDOS.DATA_HORA, LISTAPEDIDOS.DATA_VENCIMENTO, CLIENTES.NOME, SUM(LISTAPEDIDOS.VALOR_TOTAL),
            forma_pgto.tipo, especie_pgto.tipo, NATUREZA_OPERACAO.tipo, LISTAPEDIDOS.ID_CLIENTE, LISTAPEDIDOS.STATUS, LISTAPEDIDOS.NOTA_FISCAL, LISTAPEDIDOS.NOTA_FISCAL_SERV, LISTAPEDIDOS.CUPOM_FISCAL, LISTAPEDIDOS.NFCE_NUMERO, LISTAPEDIDOS.ID_VENDEDOR, LISTAPEDIDOS.ID_DEPTO,
            CLIENTES.id_classe, CLIENTES.id_regiao
            FROM LISTAPEDIDOS
            LEFT JOIN funcionarios ON (funcionarios.id_funcionario = listapedidos.id_vendedor)
            LEFT JOIN natureza_operacao ON (natureza_operacao.id_natureza = listapedidos.id_natureza)
            LEFT JOIN clientes ON (clientes.id_cliente = listapedidos.id_cliente)
            LEFT JOIN especie_pgto ON (especie_pgto.id_especie = listapedidos.id_especie)
            LEFT JOIN forma_pgto ON (forma_pgto.id_forma = listapedidos.id_forma)
            WHERE (LISTAPEDIDOS.STATUS = 2) AND ((LISTAPEDIDOS.OPERACAO = 1) or (LISTAPEDIDOS.OPERACAO = 6) or (LISTAPEDIDOS.OPERACAO = 12))
            AND (natureza_operacao.tipo <> 2) AND (natureza_operacao.processo <> 3)
            GROUP BY LISTAPEDIDOS.ID_PEDIDO, LISTAPEDIDOS.TIPO, LISTAPEDIDOS.DATA_HORA, LISTAPEDIDOS.DATA_VENCIMENTO, CLIENTES.NOME, forma_pgto.tipo, especie_pgto.tipo, NATUREZA_OPERACAO.tipo, LISTAPEDIDOS.ID_CLIENTE, LISTAPEDIDOS.STATUS, LISTAPEDIDOS.NOTA_FISCAL, LISTAPEDIDOS.NOTA_FISCAL_SERV, LISTAPEDIDOS.CUPOM_FISCAL, LISTAPEDIDOS.NFCE_NUMERO, LISTAPEDIDOS.ID_VENDEDOR, LISTAPEDIDOS.ID_DEPTO, CLIENTES.id_classe, CLIENTES.id_regiao
            """,

        ["L_VENDAS_REGIAO"] = """
            CREATE OR ALTER VIEW L_VENDAS_REGIAO (
                ID_PEDIDO, TIPO, DATA_HORA, DATA_VENCIMENTO, REGIAO, UF, VALOR_PEDIDO, 
                TIPO_FP, TIPO_EP, TIPO_NAT, ID_CLIENTE, STATUS, NOTA_FISCAL, NOTA_FISCAL_SERV, 
                CUPOM_FISCAL, NFCE_NUMERO, ID_VENDEDOR, ID_DEPTO, ID_CLASSE, ID_REGIAO
            ) AS
            SELECT LISTAPEDIDOS.ID_PEDIDO, LISTAPEDIDOS.TIPO, LISTAPEDIDOS.DATA_HORA, LISTAPEDIDOS.DATA_VENCIMENTO,
            CASE WHEN (LISTAPEDIDOS.id_propriedade IS NULL OR (LISTAPEDIDOS.id_propriedade = 0)) THEN R1.cidade ELSE R2.cidade END, CASE WHEN (LISTAPEDIDOS.id_propriedade IS NULL OR (LISTAPEDIDOS.id_propriedade = 0)) THEN R1.uf ELSE R2.uf END,
            SUM(LISTAPEDIDOS.VALOR_TOTAL),
            forma_pgto.tipo, especie_pgto.tipo, NATUREZA_OPERACAO.tipo, LISTAPEDIDOS.ID_CLIENTE, LISTAPEDIDOS.STATUS, LISTAPEDIDOS.NOTA_FISCAL, LISTAPEDIDOS.NOTA_FISCAL_SERV, LISTAPEDIDOS.CUPOM_FISCAL, LISTAPEDIDOS.NFCE_NUMERO, LISTAPEDIDOS.ID_VENDEDOR, LISTAPEDIDOS.ID_DEPTO,
            CLIENTES.id_classe, CASE WHEN (LISTAPEDIDOS.id_propriedade IS NULL OR (LISTAPEDIDOS.id_propriedade = 0)) THEN R1.id_regiao ELSE R2.id_regiao END
            FROM LISTAPEDIDOS
            LEFT JOIN funcionarios ON (funcionarios.id_funcionario = listapedidos.id_vendedor)
            LEFT JOIN natureza_operacao ON (natureza_operacao.id_natureza = listapedidos.id_natureza)
            LEFT JOIN clientes ON (clientes.id_cliente = listapedidos.id_cliente)
            LEFT JOIN clientes_propriedades ON ((clientes_propriedades.id_propriedade = listapedidos.id_propriedade) AND (clientes_propriedades.id_cliente = listapedidos.id_cliente))
            LEFT JOIN regioes R1 ON (R1.id_regiao = clientes.id_regiao)
            LEFT JOIN regioes R2 ON (R2.id_regiao = clientes_propriedades.id_regiao)
            LEFT JOIN especie_pgto ON (especie_pgto.id_especie = listapedidos.id_especie)
            LEFT JOIN forma_pgto ON (forma_pgto.id_forma = listapedidos.id_forma)
            WHERE (LISTAPEDIDOS.STATUS = 2) AND ((LISTAPEDIDOS.OPERACAO = 1) or (LISTAPEDIDOS.OPERACAO = 6) or (LISTAPEDIDOS.OPERACAO = 12))
            AND (natureza_operacao.tipo <> 2) AND (natureza_operacao.processo <> 3)
            GROUP BY LISTAPEDIDOS.ID_PEDIDO, LISTAPEDIDOS.TIPO, LISTAPEDIDOS.DATA_HORA, LISTAPEDIDOS.DATA_VENCIMENTO, LISTAPEDIDOS.id_propriedade, R1.CIDADE, R2.CIDADE, R1.UF, R2.UF, forma_pgto.tipo, especie_pgto.tipo, NATUREZA_OPERACAO.tipo, LISTAPEDIDOS.ID_CLIENTE, LISTAPEDIDOS.STATUS, LISTAPEDIDOS.NOTA_FISCAL, LISTAPEDIDOS.NOTA_FISCAL_SERV, LISTAPEDIDOS.CUPOM_FISCAL, LISTAPEDIDOS.NFCE_NUMERO, LISTAPEDIDOS.ID_VENDEDOR, LISTAPEDIDOS.ID_DEPTO, CLIENTES.id_classe, R1.id_regiao, R2.id_regiao
            """,

        ["DASH_CLIENTES"] = """
            CREATE OR ALTER VIEW DASH_CLIENTES AS
            SELECT
                c.ID_CLIENTE             AS id_firebird,
                COALESCE(NULLIF(TRIM(c.NOME), ''), 'CLIENTE SEM NOME') AS nome,
                COALESCE(c.CPF_CNPJ, '') AS documento,
                COALESCE(c.EMAIL, '')    AS email,
                COALESCE(cd.FONE_RES, cd.CELULAR, '') AS telefone,
                COALESCE(r.CIDADE, '')   AS cidade,
                COALESCE(r.UF, '')       AS estado,
                (CASE c.CLASSIFICACAO
                    WHEN 0 THEN 'NAO DEFINIDO'
                    WHEN 1 THEN 'INATIVO'
                    WHEN 2 THEN 'RUIM'
                    WHEN 3 THEN 'REGULAR'
                    WHEN 4 THEN 'BOM'
                    WHEN 5 THEN 'OTIMO'
                    WHEN 6 THEN 'PREFERENCIAL'
                    WHEN 96 THEN 'PENDENTE'
                    WHEN 97 THEN 'EM COBRANCA'
                    WHEN 98 THEN 'INADIMPLENTE'
                    WHEN 99 THEN 'NEGATIVO'
                    ELSE 'OUTROS'
                END)                     AS classificacao,
                CAST(c.DATA_CADASTRO AS DATE) AS data_cadastro,
                (CASE WHEN c.CLASSIFICACAO = 1 THEN 0 ELSE 1 END) AS ativo
            FROM CLIENTES c
            LEFT JOIN REGIOES r ON r.ID_REGIAO = c.ID_REGIAO
            LEFT JOIN CLIENTES_DADOS cd ON cd.ID_CLIENTE = c.ID_CLIENTE
            """,

        ["DASH_PRODUTOS"] = """
            CREATE OR ALTER VIEW DASH_PRODUTOS AS
            SELECT 
                P.ID_PRODUTO         AS id_firebird,
                P.CODIGO_BARRA       AS codigo,
                P.DESCRICAO          AS nome,
                P.DESCRICAO          AS descricao,
                COALESCE(cat.DESCRICAO, '') AS categoria,
                COALESCE(L.NOME, P.MARCA, '') AS marca,
                COALESCE(pp.PRECO_TABELA, 0) AS preco,
                COALESCE(pp.PRECO_CUSTO, 0) AS custo,
                COALESCE(P.ESTOQUE, 0) AS estoque,
                COALESCE(P.ESTOQUE_MIN, 0) AS estoque_minimo,
                CASE WHEN COALESCE(P.BLOQUEADO, 0) = 1 THEN 0 ELSE 1 END AS ativo,
                COALESCE(P.REF, '')  AS referencia,
                COALESCE(P.CODIGO_FAB, '') AS codigo_fabrica
            FROM PRODUTOS P
            LEFT JOIN CATEGORIAS cat ON cat.ID_CATEGORIA = P.ID_CATEGORIA
            LEFT JOIN PRODUTO_PRECOS pp ON pp.ID_PRODUTO = P.ID_PRODUTO
            LEFT JOIN LABORATORIOS L ON L.ID_LABORATORIO = P.ID_MARCA
            WHERE P.TIPO = 2
            """,

        ["DASH_VENDEDORES"] = """
            CREATE OR ALTER VIEW DASH_VENDEDORES AS
            SELECT
                ID_FUNCIONARIO AS id_firebird,
                NOME AS nome,
                '' AS email,
                MOB_ACESSO AS ativo
            FROM FUNCIONARIOS
            """,

        ["DASH_VENDAS"] = """
            RECREATE VIEW DASH_VENDAS AS
            SELECT
                p.ID_PEDIDO                                              AS id_firebird,
                CAST(p.ID_PEDIDO AS VARCHAR(20))                         AS numero_pedido,
                CAST(p.DATA_HORA AS DATE)                                AS data_venda,
                p.DATA_HORA_PROC                                         AS data_hora_proc,
                p.ID_CLIENTE                                             AS cliente_id_firebird,
                p.ID_VENDEDOR                                            AS vendedor_id_firebird,
                MAX((CASE WHEN nat.TIPO = 2 THEN -1 ELSE 1 END) * (COALESCE(p.VALOR_PEDIDO, 0) + COALESCE(p.VALOR_FRETE, 0) + COALESCE(p.OUTRAS_DESPESAS, 0) + COALESCE(p.VALOR_ACRESCIMO, 0) + COALESCE(p.VALOR_IPI, 0) + COALESCE(p.VALOR_ICMS_SUB, 0) - COALESCE(p.VALOR_DESCONTO, 0))) AS valor_total,
                (CASE WHEN nat.TIPO = 2 THEN -1 ELSE 1 END) * COALESCE(SUM(pi.VALOR_CUSTO), 0) AS valor_custo,
                (CASE WHEN nat.TIPO = 2 THEN -1 ELSE 1 END) * MAX(COALESCE(p.VALOR_DESCONTO, 0)) AS valor_desconto,
                CASE p.STATUS 
                    WHEN 0 THEN 'ABERTO'
                    WHEN 1 THEN 'ABERTO'
                    WHEN 9 THEN 'CANCELADO' 
                    ELSE 'FATURADO' 
                END                                                      AS status,
                MAX(COALESCE(pr.MARCA, ''))                              AS marca,
                MAX(COALESCE(cat.DESCRICAO, ''))                         AS categoria,
                MAX(COALESCE(esp.DESCRICAO, 'Não Informada'))            AS especie,
                p.ID_DEPTO                                               AS depto_id,
                p.DATA_VENCIMENTO                                        AS data_vencimento,
                p.ID_NATUREZA                                            AS natureza_id,
                nat.TIPO                                                 AS natureza_tipo,
                nat.PROCESSO                                             AS natureza_processo
            FROM PEDIDOS p
            JOIN PEDIDO_ITENS pi ON pi.ID_PEDIDO = p.ID_PEDIDO
            LEFT JOIN PRODUTOS pr ON pr.ID_PRODUTO = pi.ID_PRODUTO
            LEFT JOIN CATEGORIAS cat ON cat.ID_CATEGORIA = pr.ID_CATEGORIA
            LEFT JOIN PEDIDOS_DOCS pd ON pd.ID_PEDIDO = p.ID_PEDIDO
            LEFT JOIN ESPECIE_PGTO esp ON esp.ID_ESPECIE = pd.ID_ESPECIE
            LEFT JOIN NATUREZA_OPERACAO nat ON nat.ID_NATUREZA = p.ID_NATUREZA
            WHERE p.STATUS IN (0, 1, 2, 9)
              AND p.TIPO = 1
              AND nat.OPERACAO IN (1, 6, 12)
              AND (nat.PROCESSO <> 3 OR nat.PROCESSO IS NULL)
            GROUP BY p.ID_PEDIDO, p.DATA_HORA, p.DATA_HORA_PROC, p.ID_CLIENTE, p.ID_VENDEDOR, p.STATUS, p.ID_DEPTO, p.DATA_VENCIMENTO, p.ID_NATUREZA, nat.TIPO, nat.PROCESSO
            """,

        ["DASH_VENDAS_ITENS"] = """
            CREATE OR ALTER VIEW DASH_VENDAS_ITENS AS
            SELECT
                ((pi.ID_PEDIDO * 1000) + pi.ID_ITEM)                     AS id_firebird,
                pi.ID_PEDIDO                                             AS venda_id_firebird,
                pi.ID_PRODUTO                                            AS produto_id_firebird,
                (CASE WHEN nat.TIPO = 2 THEN -1 ELSE 1 END) * COALESCE(pi.QTDE, 0) AS quantidade,
                COALESCE(pi.VALOR_UNITARIO, 0)                           AS preco_unitario,
                COALESCE(pi.VALOR_CUSTO, 0)                              AS custo_unitario,
                (CASE WHEN nat.TIPO = 2 THEN -1 ELSE 1 END) * COALESCE(pi.VALOR_TOTAL, 0) AS valor_total,
                COALESCE(f.NOME, '')                                     AS vendedor,
                COALESCE(pr.DESCRICAO, '')                               AS produto,
                COALESCE(pr.MARCA, '')                                   AS marca,
                COALESCE(cat.DESCRICAO, '')                              AS categoria,
                p.ID_DEPTO                                               AS depto_id,
                p.ID_NATUREZA                                            AS natureza_id,
                nat.TIPO                                                 AS natureza_tipo,
                nat.PROCESSO                                             AS natureza_processo
            FROM PEDIDO_ITENS pi
            JOIN PEDIDOS p ON p.ID_PEDIDO = pi.ID_PEDIDO
            LEFT JOIN PRODUTOS pr ON pr.ID_PRODUTO = pi.ID_PRODUTO
            LEFT JOIN CATEGORIAS cat ON cat.ID_CATEGORIA = pr.ID_CATEGORIA
            LEFT JOIN FUNCIONARIOS f ON f.ID_FUNCIONARIO = p.ID_VENDEDOR
            LEFT JOIN NATUREZA_OPERACAO nat ON nat.ID_NATUREZA = p.ID_NATUREZA
            WHERE p.STATUS IN (0, 1, 2, 9)
              AND p.TIPO = 1
              AND nat.OPERACAO IN (1, 6, 12)
              AND (nat.PROCESSO <> 3 OR nat.PROCESSO IS NULL)
            """,

        ["DASH_FINANCEIRO"] = """
            CREATE OR ALTER VIEW DASH_FINANCEIRO AS
            SELECT
                con.ID_CONTA                                             AS id_firebird,
                CASE WHEN con.DC = 1 THEN 'RECEBER' ELSE 'PAGAR' END    AS tipo,
                CASE con.TIPO
                    WHEN 1 THEN 'TITULO COMUM'
                    WHEN 3 THEN 'TITULO RENEGOCIADO'
                    WHEN 4 THEN 'TITULO COMUM'
                    WHEN 6 THEN 'TITULO CHEQUE DEVOLVIDO'
                    ELSE 'OUTROS'
                END                                                      AS tipo_documento,
                COALESCE(con.DESCRICAO, '')                              AS descricao,
                con.ID_CLIENTE                                           AS cliente_id_firebird,
                con.ID_CAIXA                                             AS caixa_id_firebird,
                con.DATA_EMISSAO                                         AS data_emissao,
                con.DATA_VENCIMENTO                                      AS data_vencimento,
                con.DATA_PAGAMENTO                                       AS data_pagamento,
                COALESCE(con.VALOR, 0)                                   AS valor,
                COALESCE(con.VALOR_PAGO, 0)                              AS valor_pago,
                (CASE WHEN COALESCE(con.BAIXA, 0) = 1 THEN 'PAGO' ELSE 'ABERTO' END) AS status_pagamento,
                con.ID_DEPTO                                             AS depto_id,
                (SELECT FIRST 1 ID_CENTRO FROM CONTAS_DETALHES cd WHERE cd.ID_CONTA = con.ID_CONTA) AS centro_custo
            FROM CONTAS con
            WHERE con.DATA_EMISSAO IS NOT NULL
            """,

        ["DASH_FILIAIS"] = """
            CREATE OR ALTER VIEW DASH_FILIAIS AS
            SELECT
                d.ID_DEPTO                                               AS depto_id,
                COALESCE(TRIM(d.DESCRICAO), '')                          AS nome,
                COALESCE(TRIM(e.CNPJ), '')                               AS documento,
                COALESCE(TRIM(d.OP_ESTOQUE), '')                         AS centro_custo,
                COALESCE(c.ID_EMPRESA, 1)                                AS empresa_erp,
                CASE WHEN c.ID_EMPRESA = 1 THEN 1 ELSE 0 END             AS is_default
            FROM DEPARTAMENTOS d
            LEFT JOIN CONFIG c ON c.DEPTO_PADRAO = d.ID_DEPTO
            LEFT JOIN EMPRESA e ON e.ID_EMPRESA = c.ID_EMPRESA
            """,
    };

    private static readonly (string TableName, string PkColumn)[] TrackedTables = new[]
    {
        ("PRODUTOS", "ID_PRODUTO"),
        ("PRODUTO_DEPTOS", "ID_PRODUTO"),
        ("PRODUTO_PRECOS", "ID_PRODUTO"),
        ("CLIENTES", "ID_CLIENTE"),
        ("FUNCIONARIOS", "ID_FUNCIONARIO"),
        ("PEDIDOS", "ID_PEDIDO"),
        ("PEDIDO_ITENS", "ID_PEDIDO"),
        ("CONTAS", "ID_CONTA"),
        ("CAIXAS", "ID_CAIXA"),
        ("FORNECEDORES", "ID_FORNECEDOR"),
        ("NOTAS", "ID_NOTA"),
        ("FORMA_PGTO", "ID_FORMA"),
        ("ESPECIE_PGTO", "ID_ESPECIE"),
        ("NATUREZA_OPERACAO", "ID_NATUREZA"),
        ("TABELA_PRECO", "ID_TABELA")
    };

    private static async Task<bool> TableExistsAsync(FbConnection conn, string table)
    {
        await using var tx = await conn.BeginTransactionAsync();
        await using var cmd = new FbCommand(
            "SELECT 1 FROM RDB$RELATIONS WHERE RDB$RELATION_NAME = @T",
            conn, tx);
        cmd.Parameters.AddWithValue("@T", table);
        var result = await cmd.ExecuteScalarAsync();
        await tx.CommitAsync();
        return result != null;
    }
}
