using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace ColiseuSales.Configurator
{
    public class SettingsManager
    {
        private readonly string _appSettingsPath;

        public SettingsManager()
        {
            // Para single-file publish, AppDomain.CurrentDomain.BaseDirectory aponta para
            // a pasta TEMP de extração do runtime — NÃO a pasta real do exe.
            // Environment.ProcessPath retorna o caminho correto do executável em qualquer modo.
            var exeDir    = Path.GetDirectoryName(Environment.ProcessPath ?? AppDomain.CurrentDomain.BaseDirectory)
                            ?? AppDomain.CurrentDomain.BaseDirectory;
            var localPath = Path.Combine(exeDir, "appsettings.json");

            // 1ª prioridade: appsettings.json na mesma pasta do Configurador (caso mais comum —
            // o Worker é sempre instalado na mesma pasta que o Configurador).
            if (File.Exists(localPath))
            {
                _appSettingsPath = localPath;
                return;
            }

            // 2ª prioridade: pasta do Worker via Registro (instalação anterior em pasta diferente)
            var workerDir  = GetWorkerInstallDir();
            var workerPath = workerDir != null ? Path.Combine(workerDir, "appsettings.json") : null;
            if (workerPath != null && File.Exists(workerPath))
            {
                _appSettingsPath = workerPath;
                return;
            }

            // 3ª prioridade: caminho de desenvolvimento local (repositório)
            var devPath = Path.GetFullPath(Path.Combine(exeDir, "..", "..", "..", "..", "worker", "appsettings.json"));
            if (File.Exists(devPath))
            {
                _appSettingsPath = devPath;
                return;
            }

            // Fallback: mesma pasta do Configurador (será criado ao salvar pela 1ª vez)
            _appSettingsPath = localPath;
        }

        /// <summary>
        /// Obtém o diretório de instalação do Worker consultando o Registro do Windows.
        /// Retorna null se o serviço não estiver registrado.
        /// </summary>
        private static string? GetWorkerInstallDir()
        {
            try
            {
                const string svcKey = @"SYSTEM\CurrentControlSet\Services\ColiseuSales Worker";
                using var key = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(svcKey, false);
                var imagePath = key?.GetValue("ImagePath") as string;
                if (string.IsNullOrWhiteSpace(imagePath)) return null;

                // ImagePath pode ter aspas e argumentos: "C:\foo\bar.exe" --flag
                var exePath = imagePath.Trim('"').Split('"')[0].Trim();
                return Path.GetDirectoryName(exePath);
            }
            catch { return null; }
        }

        public JsonElement ReadSettings()
        {
            // IMPORTANTE: NÃO chamar CreateDefaultSettings() aqui automaticamente.
            // Criar defaults silenciosamente sobrescreveria configurações válidas
            // se o _appSettingsPath apontar para um caminho errado ou o arquivo estiver ausente.
            // Retorna JsonElement vazio — LoadSettings() usa os defaults da UI como fallback.
            if (!File.Exists(_appSettingsPath))
                return default;

            try
            {
                string jsonString = File.ReadAllText(_appSettingsPath);
                using var doc = JsonDocument.Parse(jsonString);
                return doc.RootElement.Clone();
            }
            catch
            {
                // JSON inválido — retorna vazio, não sobrescreve
                return default;
            }
        }

        public void UpdateSettings(string firebirdPath, string firebirdUser, string firebirdPassword,
            string vpsBaseUrl, string vpsApiKey, string identityBaseUrl, string tenantId,
            int catalogSyncInterval = 5, int orderSyncIntervalSeconds = 30,
            int maxPoolSize = 30, int connectionTimeout = 60,
            bool atendenteEnabled = false, string atendenteBaseUrl = "", string atendenteApiKey = "",
            bool acEnabled = false, string acBaseUrl = "", string acApiKey = "",
            bool dashEnabled = false, string dashBaseUrl = "", string dashApiKey = "",
            bool garantiasEnabled = false, string garantiasBaseUrl = "", string garantiasApiKey = "",
            bool wireCrypt = false, string spVariant = "Standard",
            bool nexusEnabled = false, string nexusBaseUrl = "", string nexusApiKey = "",
            bool visionEnabled = false, string visionBaseUrl = "", string visionApiKey = "",
            string serviceSuffix = "", bool vpsEnabled = true)
        {
            if (!File.Exists(_appSettingsPath))
                CreateDefaultSettings();

            string jsonString = File.ReadAllText(_appSettingsPath);
            var jsonNode = JsonNode.Parse(jsonString);

            if (jsonNode == null)
                throw new InvalidOperationException("Falha ao fazer o parse do JSON das configurações.");

            // FIX: Parsear a string da UI (ex: "10.10.100.212/7070:APPSALES") em campos separados
            // que FirebirdOptions.BuildConnectionString() espera: Host, Port, Database.
            // Sem isso o Worker tentava DataSource=localhost;Port=3050;Database=host/port:db — errado!
            var (fbHost, fbPort, fbDatabase) = ParseFirebirdPath(firebirdPath);

            // Update Worker Node
            if (jsonNode["Worker"] == null) jsonNode["Worker"] = new JsonObject();
            jsonNode["Worker"]["CatalogSyncIntervalMinutes"] = catalogSyncInterval;
            jsonNode["Worker"]["OrderSyncIntervalSeconds"]   = orderSyncIntervalSeconds;
            jsonNode["Worker"]["ServiceSuffix"]              = serviceSuffix;

            // Update Firebird Node — agora com Host/Port/Database separados + WireCrypt + SpVariant
            if (jsonNode["Firebird"] == null) jsonNode["Firebird"] = new JsonObject();
            jsonNode["Firebird"]["Host"]      = fbHost;
            jsonNode["Firebird"]["Port"]      = fbPort;
            jsonNode["Firebird"]["Database"]  = fbDatabase;
            jsonNode["Firebird"]["User"]      = firebirdUser;
            jsonNode["Firebird"]["Password"]  = firebirdPassword;
            jsonNode["Firebird"]["Charset"]   = "NONE";
            jsonNode["Firebird"]["Dialect"]   = 3;
            jsonNode["Firebird"]["WireCrypt"] = wireCrypt;
            jsonNode["Firebird"]["SpVariant"] = spVariant;
            jsonNode["Firebird"]["Pooling"]   = true;
            jsonNode["Firebird"]["MinPoolSize"] = 1;
            jsonNode["Firebird"]["MaxPoolSize"] = maxPoolSize;
            jsonNode["Firebird"]["ConnectionTimeout"] = connectionTimeout;

            // Update VpsApi Node
            if (jsonNode["VpsApi"] == null) jsonNode["VpsApi"] = new JsonObject();
            jsonNode["VpsApi"]["Enabled"]   = vpsEnabled;
            jsonNode["VpsApi"]["BaseUrl"]   = vpsBaseUrl;
            jsonNode["VpsApi"]["ApiKey"]    = vpsApiKey;
            jsonNode["VpsApi"]["CompanyId"] = tenantId; // FIX: O CompanyId DEVE ser salvo aqui para o SyncOrdersJob poder carregar as filiais.

            // Update IdentityApi Node
            if (jsonNode["IdentityApi"] == null) jsonNode["IdentityApi"] = new JsonObject();
            jsonNode["IdentityApi"]["BaseUrl"]  = identityBaseUrl;
            jsonNode["IdentityApi"]["TenantId"] = tenantId;
            jsonNode["IdentityApi"]["InternalApiKey"] = "Coliseu2026!IdentitySuperSecretKeyOauth20";

            // Update AtendenteApi Node
            if (jsonNode["AtendenteApi"] == null) jsonNode["AtendenteApi"] = new JsonObject();
            jsonNode["AtendenteApi"]["Enabled"] = atendenteEnabled;
            jsonNode["AtendenteApi"]["BaseUrl"] = atendenteBaseUrl;
            jsonNode["AtendenteApi"]["ApiKey"]  = atendenteApiKey;

            // Update AutoCenterApi Node
            if (jsonNode["AutoCenterApi"] == null) jsonNode["AutoCenterApi"] = new JsonObject();
            jsonNode["AutoCenterApi"]["Enabled"] = acEnabled;
            jsonNode["AutoCenterApi"]["BaseUrl"] = acBaseUrl;
            jsonNode["AutoCenterApi"]["InternalApiKey"]  = acApiKey;

            // Update DashboardApi Node
            if (jsonNode["DashboardApi"] == null) jsonNode["DashboardApi"] = new JsonObject();
            jsonNode["DashboardApi"]["Enabled"] = dashEnabled;
            jsonNode["DashboardApi"]["BaseUrl"] = dashBaseUrl;
            jsonNode["DashboardApi"]["InternalApiKey"]  = dashApiKey;
            jsonNode["DashboardApi"]["TimeoutSeconds"]  = 30;

            // Update NexusApi Node
            if (jsonNode["NexusApi"] == null) jsonNode["NexusApi"] = new JsonObject();
            jsonNode["NexusApi"]["Enabled"] = nexusEnabled;
            jsonNode["NexusApi"]["BaseUrl"] = nexusBaseUrl;
            jsonNode["NexusApi"]["InternalApiKey"]  = nexusApiKey;
            jsonNode["NexusApi"]["TimeoutSeconds"]  = 30;

            // Update VisionApi Node
            if (jsonNode["VisionApi"] == null) jsonNode["VisionApi"] = new JsonObject();
            jsonNode["VisionApi"]["Enabled"] = visionEnabled;
            jsonNode["VisionApi"]["BaseUrl"] = visionBaseUrl;
            jsonNode["VisionApi"]["InternalApiKey"]  = visionApiKey;
            jsonNode["VisionApi"]["TimeoutSeconds"]  = 30;

            // Update GarantiasApi Node
            if (jsonNode["GarantiasApi"] == null) jsonNode["GarantiasApi"] = new JsonObject();
            jsonNode["GarantiasApi"]["Enabled"] = garantiasEnabled;
            jsonNode["GarantiasApi"]["BaseUrl"] = garantiasBaseUrl;
            jsonNode["GarantiasApi"]["InternalApiKey"]  = garantiasApiKey;

            // Serialize and Save (Preserves formatting with WriteIndented)
            var options = new JsonSerializerOptions { WriteIndented = true };
            string updatedJsonString = jsonNode.ToJsonString(options);

            File.WriteAllText(_appSettingsPath, updatedJsonString);
        }

        /// <summary>
        /// Parseia a string de conexão Firebird da UI em campos separados.
        /// Suporta formatos:
        ///   "host/port:database"    → (host, port, database)  ex: 10.10.0.212/7070:APPSALES
        ///   "host:database"         → (host, 3050, database)  ex: servidor:APPSALES
        ///   "C:\caminho\banco.fdb"  → (localhost, 3050, caminho)
        ///   "APPSALES"             → (localhost, 3050, APPSALES)
        /// </summary>
        internal static (string host, int port, string database) ParseFirebirdPath(string path)
        {
            if (string.IsNullOrWhiteSpace(path))
                return ("localhost", 3050, path);

            // Caminho local: começa com letra+: (Windows) ou \ ou / e não tem host
            if (System.IO.Path.IsPathRooted(path) || path.StartsWith("\\\\"))
                return ("localhost", 3050, path);

            // Formato "host/port:database" ou "host:database"
            // O último ':' separa host(:port) de database APENAS se houver host válido antes
            var colonIdx = path.IndexOf(':');
            if (colonIdx > 0)
            {
                var hostPart = path.Substring(0, colonIdx);
                var dbPart   = path.Substring(colonIdx + 1);

                // host pode ter /port
                var slashIdx = hostPart.IndexOf('/');
                if (slashIdx >= 0)
                {
                    var host    = hostPart.Substring(0, slashIdx);
                    var portStr = hostPart.Substring(slashIdx + 1);
                    var port    = int.TryParse(portStr, out var p) ? p : 3050;
                    return (host, port, dbPart);
                }

                // "host:database" sem porta explícita
                return (hostPart, 3050, dbPart);
            }

            // Sem ':' — é um alias local (ex: "APPSALES")
            return ("localhost", 3050, path);
        }

        private void CreateDefaultSettings()
        {
            // Construção programática — evita problemas de escape em strings verbatim
            var root = new JsonObject
            {
                ["Worker"] = new JsonObject
                {
                    ["CatalogSyncIntervalMinutes"] = 5,
                    ["OrderSyncIntervalSeconds"]   = 30,
                    ["HealthCheckIntervalMinutes"] = 5
                },
                ["Firebird"] = new JsonObject
                {
                    ["Host"]              = "localhost",
                    ["Port"]              = 3050,
                    ["Database"]          = "",
                    ["User"]              = "SYSDBA",
                    ["Password"]          = "masterkey",
                    ["Charset"]           = "NONE",
                    ["Dialect"]           = 3,
                    ["WireCrypt"]         = false,
                    ["SpVariant"]         = "Standard",
                    ["Pooling"]           = true,
                    ["MinPoolSize"]       = 1,
                    ["MaxPoolSize"]       = 30,
                    ["ConnectionTimeout"] = 60
                },
                ["VpsApi"] = new JsonObject
                {
                    ["Enabled"] = true,
                    ["BaseUrl"] = "https://licencas.coliseusistemas.com.br",
                    ["ApiKey"]  = ""
                },
                ["IdentityApi"] = new JsonObject
                {
                    ["BaseUrl"]  = "https://adminlicencas.coliseusistemas.com.br",
                    ["TenantId"] = "00000000-0000-0000-0000-000000000000",
                    ["InternalApiKey"] = "Coliseu2026!IdentitySuperSecretKeyOauth20"
                },
                ["AtendenteApi"] = new JsonObject
                {
                    ["Enabled"] = false,
                    ["BaseUrl"] = "",
                    ["ApiKey"]  = ""
                },
                ["DashboardApi"] = new JsonObject
                {
                    ["Enabled"] = false,
                    ["BaseUrl"] = "",
                    ["InternalApiKey"]  = "",
                    ["TimeoutSeconds"] = 30
                },
                ["NexusApi"] = new JsonObject
                {
                    ["Enabled"] = false,
                    ["BaseUrl"] = "",
                    ["InternalApiKey"]  = "",
                    ["TimeoutSeconds"] = 30
                },
                ["VisionApi"] = new JsonObject
                {
                    ["Enabled"] = false,
                    ["BaseUrl"] = "",
                    ["InternalApiKey"]  = "",
                    ["TimeoutSeconds"] = 30
                },
                ["GarantiasApi"] = new JsonObject
                {
                    ["Enabled"] = false,
                    ["BaseUrl"] = "",
                    ["InternalApiKey"]  = ""
                },
            };

            var options = new JsonSerializerOptions { WriteIndented = true };
            File.WriteAllText(_appSettingsPath, root.ToJsonString(options));
        }

    }
}
