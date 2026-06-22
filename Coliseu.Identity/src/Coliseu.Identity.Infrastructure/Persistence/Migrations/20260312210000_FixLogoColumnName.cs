using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Coliseu.Identity.Infrastructure.Persistence.Migrations;

/// <summary>
/// Corrige nome da coluna de logo: logo_base64 → LogoBase64 (PascalCase EF).
/// Self-healing: funciona se a coluna existe com nome errado, certo, ou não existe.
/// </summary>
public partial class FixLogoColumnName : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        if (migrationBuilder.ActiveProvider == "Npgsql.EntityFrameworkCore.PostgreSQL")
        {
            migrationBuilder.Sql(@"
                DO $$
                BEGIN
                    -- Caso 1: coluna existe com nome errado → renomeia
                    IF EXISTS (
                        SELECT 1 FROM information_schema.columns
                        WHERE table_name = 'companies' AND column_name = 'logo_base64'
                    ) THEN
                        ALTER TABLE companies RENAME COLUMN ""logo_base64"" TO ""LogoBase64"";
                    -- Caso 2: coluna não existe nem com nome certo → cria
                    ELSIF NOT EXISTS (
                        SELECT 1 FROM information_schema.columns
                        WHERE table_name = 'companies' AND column_name = 'LogoBase64'
                    ) THEN
                        ALTER TABLE companies ADD COLUMN ""LogoBase64"" TEXT;
                    END IF;
                    -- Caso 3: coluna já existe com nome certo → nada a fazer
                END
                $$;
            ");
        }
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        // Nada — a coluna LogoBase64 é removida pela Down() de AddLogoToCompany
    }
}
