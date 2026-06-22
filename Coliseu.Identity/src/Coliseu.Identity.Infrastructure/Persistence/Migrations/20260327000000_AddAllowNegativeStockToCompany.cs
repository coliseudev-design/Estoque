using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Coliseu.Identity.Infrastructure.Persistence.Migrations;

/// <summary>
/// Adiciona campo AllowNegativeStock (BOOLEAN, default false) à tabela companies.
/// Controla se o App Mobile pode vender produtos com estoque zero ou negativo.
///   false (padrão) — Bloqueia visualmente, impede adição ao carrinho
///   true            — Exibe badge "Sem Estoque" em laranja, mas mantém produto selecionável
/// </summary>
public partial class AddAllowNegativeStockToCompany : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        if (migrationBuilder.ActiveProvider == "Npgsql.EntityFrameworkCore.PostgreSQL")
        {
            migrationBuilder.Sql(@"
                DO $$
                BEGIN
                    IF NOT EXISTS (
                        SELECT 1 FROM information_schema.columns
                        WHERE table_name = 'companies' AND column_name = 'AllowNegativeStock'
                    ) THEN
                        ALTER TABLE companies
                            ADD COLUMN ""AllowNegativeStock"" BOOLEAN NOT NULL DEFAULT false;
                    END IF;
                END
                $$;
            ");
        }
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropColumn(
            name: "AllowNegativeStock",
            table: "companies");
    }
}
