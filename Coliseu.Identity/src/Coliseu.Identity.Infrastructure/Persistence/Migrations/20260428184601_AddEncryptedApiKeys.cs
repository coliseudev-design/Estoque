using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Coliseu.Identity.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddEncryptedApiKeys : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "ApiKeyEncrypted",
                table: "company_modules",
                type: "TEXT",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "CompanyKeyEncrypted",
                table: "companies",
                type: "TEXT",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "ApiKeyEncrypted",
                table: "company_modules");

            migrationBuilder.DropColumn(
                name: "CompanyKeyEncrypted",
                table: "companies");
        }
    }
}
