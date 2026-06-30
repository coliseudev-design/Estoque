namespace ColiseuSpeed.Worker.Config;

/// <summary>
/// Configurações de conexão com o banco Firebird do ERP.
/// Lidas de appsettings.json > seção "Firebird".
/// </summary>
public sealed class FirebirdOptions
{
    public const string Section = "Firebird";

    public string Host              { get; set; } = "localhost";
    public int    Port              { get; set; } = 3050;
    public string Database          { get; set; } = string.Empty;
    public string User              { get; set; } = "SYSDBA";
    public string Password          { get; set; } = string.Empty;
    public string Charset           { get; set; } = "NONE";
    public bool   Pooling           { get; set; } = true;
    public int    MinPoolSize       { get; set; } = 1;
    public int    MaxPoolSize       { get; set; } = 5;
    public int    ConnectionTimeout { get; set; } = 30;
    /// <summary>Dialeto SQL do Firebird (3 para FB 3.0+).</summary>
    public int    Dialect           { get; set; } = 3;
    /// <summary>Habilita criptografia de wire. Recomendado em produção.</summary>
    public bool   WireCrypt         { get; set; } = true;
    /// <summary>Usa a SP com mais parâmetros (versão Autocenter)</summary>
    public bool   UseExtendedSpVariant { get; set; } = true;

    /// <summary>Connection string formatada para FirebirdSql.Data.FirebirdClient.</summary>
    public string BuildConnectionString() =>
        $"DataSource={Host};Port={Port};Database={Database};" +
        $"User ID={User};Password={Password};" +
        $"Charset={Charset};Dialect={Dialect};" +
        $"Pooling={Pooling};Min Pool Size={MinPoolSize};Max Pool Size={MaxPoolSize};" +
        $"Connection Timeout={ConnectionTimeout};" +
        $"WireCrypt={(WireCrypt ? "Enabled" : "Disabled")};";

    /// <summary>
    /// Validação deixada em branco pois a configuração real (Banco/Senha) vem do Coliseu.Identity dinamicamente.
    /// </summary>
    public void Validate()
    {
        // ... validados dinamicamente agora
    }
}
