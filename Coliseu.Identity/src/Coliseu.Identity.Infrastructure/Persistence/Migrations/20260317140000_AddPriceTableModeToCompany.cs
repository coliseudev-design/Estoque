using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Coliseu.Identity.Infrastructure.Persistence.Migrations;

/// <summary>
/// Adiciona campo PriceTableMode (TEXT, default 'none') à tabela companies.
/// Controla como a tabela de preços é usada no App Mobile.
///   "none"    — Não usar tabela (preço base)
///   "product" — Usar tabela vinculada ao cliente
///   "prompt"  — Vendedor escolhe a tabela ao criar o pedido
/// </summary>
public partial class AddPriceTableModeToCompany : Migration
{
    protected override void Up(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.AddColumn<string>(
            name: "PriceTableMode",
            table: "companies",
            type: "TEXT",
            maxLength: 20,
            nullable: false,
            defaultValue: "none");
    }

    protected override void Down(MigrationBuilder migrationBuilder)
    {
        migrationBuilder.DropColumn(
            name: "PriceTableMode",
            table: "companies");
    }
}
