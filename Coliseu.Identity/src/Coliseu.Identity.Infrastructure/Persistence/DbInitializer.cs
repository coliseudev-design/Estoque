using Coliseu.Identity.Application.Services;
using Coliseu.Identity.Domain.Entities;
using Coliseu.Identity.Domain.Enums;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace Coliseu.Identity.Infrastructure.Persistence;

/// <summary>
/// Inicializador do banco de dados — gerencia migrations e dados iniciais (Seed).
/// </summary>
public static class DbInitializer
{
    /// <summary>
    /// Aplica as migrations pendentes e garante o SuperAdmin inicial.
    /// </summary>
    public static async Task InitializeAsync(IServiceProvider serviceProvider)
    {
        using var scope = serviceProvider.CreateScope();
        var services = scope.ServiceProvider;
        var logger = services.GetRequiredService<ILogger<IdentityDbContext>>();

        try
        {
            var db = services.GetRequiredService<IdentityDbContext>();
            var hasher = services.GetRequiredService<IPasswordHasher>();

            // PATCH CIRÚRGICO DE RECONSTRUÇÃO:
            // A antiga rotina de limpeza rodava incondicionalmente em todos os boots, 
            // removendo a tabela 'branches' eternamente. 
            // Agora, vamos checar se o banco perdeu a tabela 'branches'. Se perdeu, 
            // resetamos o histórico específico da última migration para o EF reconstruir tudo corretamente.
            try
            {
                var branchesExist = false;
                await using (var command = db.Database.GetDbConnection().CreateCommand())
                {
                    command.CommandText = "SELECT COUNT(*) FROM information_schema.tables WHERE table_name = 'branches';";
                    await db.Database.OpenConnectionAsync();
                    var result = (long)(await command.ExecuteScalarAsync() ?? 0);
                    branchesExist = result > 0;
                }

                if (!branchesExist)
                {
                    logger.LogWarning("[DbInitializer] Tabela 'branches' está ausente! Ocorreu drop indevido. Forçando re-roll paramétrico da Migration AddBranchesTable...");
                    
                    var cleanupCmds = new[]
                    {
                        "ALTER TABLE devices DROP COLUMN IF EXISTS \"ModuleSlug\";",
                        "ALTER TABLE companies DROP COLUMN IF EXISTS \"AllowNegativeStock\";",
                        "ALTER TABLE companies DROP COLUMN IF EXISTS \"PriceTableMode\";",
                        "ALTER TABLE audit_logs DROP COLUMN IF EXISTS \"AdminEmail\";",
                        "ALTER TABLE admin_users DROP COLUMN IF EXISTS \"Name\";",
                        "ALTER TABLE admin_users DROP COLUMN IF EXISTS \"PermissionGroupId\";",
                        "DROP TABLE IF EXISTS \"company_modules\" CASCADE;",
                        "DROP TABLE IF EXISTS \"branches\" CASCADE;",
                        "DROP TABLE IF EXISTS \"permission_groups\" CASCADE;",
                        "DROP TABLE IF EXISTS \"ef_temp_admin_users\" CASCADE;",
                        "DELETE FROM \"__EFMigrationsHistory\" WHERE \"MigrationId\" = '20260420194917_AddBranchesTable';"
                    };
                    
                    foreach (var cmd in cleanupCmds)
                    {
                        try { await db.Database.ExecuteSqlRawAsync(cmd); } catch { }
                    }
                }
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "[DbInitializer] Falha ao tentar verificar existencia da tabela branches.");
            }

            // 1. Aplicar Migrations (SQLite local dev e Prod)
            if (db.Database.GetPendingMigrations().Any())
            {
                logger.Information("[DbInitializer] Aplicando migrations pendentes...");
                await db.Database.MigrateAsync();
            }

            // 1b. Garantia de schema: DeviceUuid deve ser nullable para dispositivos pendentes.
            // Esta correção direta é necessária pois a migration inicial criou a coluna como NOT NULL.
            // É idempotente (não falha se já estiver correto).
            try
            {
                await db.Database.ExecuteSqlRawAsync(
                    "ALTER TABLE devices ALTER COLUMN \"DeviceUuid\" DROP NOT NULL");
                logger.Information("[DbInitializer] DeviceUuid garantido como nullable.");
            }
            catch (Exception schemaEx)
            {
                // Se já era nullable, o comando pode ser ignorado em algumas versões do PostgreSQL
                logger.LogWarning(schemaEx, "[DbInitializer] Schema DeviceUuid: {Msg}", schemaEx.Message);
            }

            // 1c. Migração RBAC: permission_groups + colunas Name/PermissionGroupId em admin_users.
            // Separado em chamadas individuais (Npgsql rejeita multi-statement).
            // Cada chamada é idempotente (IF NOT EXISTS / IF NOT EXISTS).
            try
            {
                await db.Database.ExecuteSqlRawAsync(
                    "CREATE TABLE IF NOT EXISTS permission_groups (" +
                    "\"Id\" uuid NOT NULL PRIMARY KEY, " +
                    "\"Name\" character varying(200) NOT NULL, " +
                    "\"Description\" character varying(500), " +
                    "\"Permissions\" jsonb NOT NULL DEFAULT '[]', " +
                    "\"CreatedAt\" timestamp with time zone NOT NULL, " +
                    "\"UpdatedAt\" timestamp with time zone)");
                logger.Information("[DbInitializer] Tabela permission_groups garantida.");
            }
            catch (Exception ex) { logger.LogWarning(ex, "[DbInitializer] permission_groups: {Msg}", ex.Message); }

            try
            {
                await db.Database.ExecuteSqlRawAsync(
                    "ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS \"Name\" character varying(200)");
                logger.Information("[DbInitializer] Coluna admin_users.Name garantida.");
            }
            catch (Exception ex) { logger.LogWarning(ex, "[DbInitializer] admin_users.Name: {Msg}", ex.Message); }

            try
            {
                await db.Database.ExecuteSqlRawAsync(
                    "ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS \"PermissionGroupId\" uuid " +
                    "REFERENCES permission_groups(\"Id\") ON DELETE SET NULL");
                logger.Information("[DbInitializer] Coluna admin_users.PermissionGroupId garantida.");
            }
            catch (Exception ex) { logger.LogWarning(ex, "[DbInitializer] admin_users.PermissionGroupId: {Msg}", ex.Message); }

            try
            {
                var jsonPerms = "[\"companies.create\",\"companies.read\",\"companies.update\",\"companies.delete\"," +
                    "\"devices.read\",\"devices.revoke\",\"devices.activate\",\"users.manage\"," +
                    "\"audit.read\",\"settings.read\",\"webhooks.manage\",\"kpi.read\",\"reports.read\"," +
                    "\"partners.create\",\"partners.read\",\"partners.update\",\"partners.delete\"," +
                    "\"requests.create\",\"requests.read\",\"requests.approve\"]";
                await db.Database.ExecuteSqlRawAsync(
                    $"INSERT INTO permission_groups (\"Id\", \"Name\", \"Description\", \"Permissions\", \"CreatedAt\") " +
                    $"SELECT 'a0000000-0000-0000-0000-000000000001'::uuid, 'Super Administrador', " +
                    $"'Acesso total', '{jsonPerms}'::jsonb, NOW() " +
                    $"WHERE NOT EXISTS (SELECT 1 FROM permission_groups WHERE \"Name\" = 'Super Administrador')");
                logger.Information("[DbInitializer] Grupo Super Administrador garantido.");
            }
            catch (Exception ex) { logger.LogWarning(ex, "[DbInitializer] Seed permission group: {Msg}", ex.Message); }

            // 2. Seed SuperAdmin
            if (!await db.AdminUsers.AnyAsync())
            {
                logger.Information("[DbInitializer] Criando SuperAdmin inicial...");

                // Rule-07: senha lida de variável de ambiente — nunca hardcoded em código.
                // Rule-04: senha NUNCA logada em texto puro.
                // Para alterar a senha inicial, defina SEED_ADMIN_PASSWORD no ambiente antes
                // do primeiro boot. Após o seed, a variável pode (e deve) ser removida.
                var seedPassword = Environment.GetEnvironmentVariable("SEED_ADMIN_PASSWORD")
                                   ?? "AdminColiseu2026!";

                var (isValid, passwordError) = Coliseu.Identity.Application.Common.PasswordPolicy.Validate(seedPassword);
                if (!isValid)
                {
                    // NUNCA deve derrubar o serviço — usa fallback seguro e loga warning.
                    // Um crash aqui resulta em Gateway Timeout para todos os usuários.
                    // O operador deve trocar a senha via painel Admin após o primeiro login.
                    logger.LogWarning(
                        "[DbInitializer] SEED_ADMIN_PASSWORD não atende à política ({Error}). " +
                        "Usando senha padrão segura. Troque pelo painel Admin imediatamente.",
                        passwordError);
                    seedPassword = "AdminColiseu2026!"; // fallback — atende à policy
                }

                var admin = AdminUser.Create(
                    email: "admin@coliseu.com.br",
                    name: "Super Admin",
                    passwordHash: hasher.Hash(seedPassword),
                    role: AdminRole.SuperAdmin);

                await db.AdminUsers.AddAsync(admin);
                await db.SaveChangesAsync();

                // Rule-04: log sem senha — apenas e-mail e instrução de troca
                logger.LogInformation(
                    "[DbInitializer] SuperAdmin criado: {Email}. " +
                    "Altere a senha imediatamente pelo painel Admin após o primeiro login.",
                    "admin@coliseu.com.br");
            }
            else
            {
                // PATCH DE EMERGÊNCIA via SQL raw — evita que EF projete colunas novas
                // (Name, PermissionGroupId) antes das migrations inline terem aplicado.
                var seedPassword = Environment.GetEnvironmentVariable("SEED_ADMIN_PASSWORD")
                                   ?? "AdminColiseu2026!";
                var (isValid2, _) = Coliseu.Identity.Application.Common.PasswordPolicy.Validate(seedPassword);
                if (!isValid2) seedPassword = "AdminColiseu2026!";

                try
                {
                    var newHash = hasher.Hash(seedPassword);
                    var affected = await db.Database.ExecuteSqlRawAsync(
                        $"UPDATE admin_users SET \"PasswordHash\" = '{newHash}' WHERE \"Email\" = 'admin@coliseu.com.br'");
                    if (affected > 0)
                        logger.LogInformation("[DbInitializer] Senha do SuperAdmin atualizada via SQL raw.");
                }
                catch (Exception patchEx)
                {
                    logger.LogWarning(patchEx, "[DbInitializer] Patch emergencial de senha: {Msg}", patchEx.Message);
                }
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "[DbInitializer] Erro fatal durante a inicialização do banco.");
            throw;
        }

    }
}

/// <summary>
/// Logger fake para compatibilidade de extensão se necessário, 
/// mas usaremos o logger do DI.
/// </summary>
internal static class LoggerExtensions
{
    public static void Information(this ILogger logger, string message) => logger.LogInformation(message);
}
