using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Coliseu.Identity.Infrastructure.Persistence.Migrations;

/// <summary>
/// Adiciona campo LogoBase64 (TEXT nullable) à tabela companies.
/// Permite armazenar a logo da empresa como Base64 (~500KB max).
///
/// Self-healing: se a coluna foi criada com nome errado (logo_base64)
/// por uma versão anterior, renomeia para LogoBase64.
/// </summary>
public partial class AddLogoToCompany : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        if (migrationBuilder.ActiveProvider == "Npgsql.EntityFrameworkCore.PostgreSQL")
        {
            migrationBuilder.Sql(@"
                DO $$
                BEGIN
                    IF EXISTS (
                        SELECT 1 FROM information_schema.columns
                        WHERE table_name = 'companies' AND column_name = 'logo_base64'
                    ) THEN
                        ALTER TABLE companies RENAME COLUMN ""logo_base64"" TO ""LogoBase64"";
                    ELSIF NOT EXISTS (
                        SELECT 1 FROM information_schema.columns
                        WHERE table_name = 'companies' AND column_name = 'LogoBase64'
                    ) THEN
                        ALTER TABLE companies ADD COLUMN ""LogoBase64"" TEXT;
                    END IF;
                END
                $$;
            ");
        }
        else
        {
            migrationBuilder.AddColumn<string>(
                name: "LogoBase64",
                table: "companies",
                type: "TEXT",
                nullable: true);
        }
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropColumn(
            name: "LogoBase64",
            table: "companies");
    }
}
