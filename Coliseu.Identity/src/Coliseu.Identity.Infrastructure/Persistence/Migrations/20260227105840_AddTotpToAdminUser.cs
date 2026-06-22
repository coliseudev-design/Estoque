using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Coliseu.Identity.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddTotpToAdminUser : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "TotpEnabled",
                table: "admin_users",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "TotpSecretEncrypted",
                table: "admin_users",
                type: "TEXT",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "TotpEnabled",
                table: "admin_users");

            migrationBuilder.DropColumn(
                name: "TotpSecretEncrypted",
                table: "admin_users");
        }
    }
}
