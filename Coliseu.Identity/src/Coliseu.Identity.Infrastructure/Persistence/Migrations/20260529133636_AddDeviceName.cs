using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Coliseu.Identity.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddDeviceName : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "Name",
                table: "devices",
                type: "TEXT",
                maxLength: 150,
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "Name",
                table: "devices");
        }
    }
}
