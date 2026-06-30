using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Coliseu.Identity.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddBranchesTable : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.Sql("DROP INDEX IF EXISTS \"IX_devices_DeviceUuid_CompanyId\";");

















            migrationBuilder.AddColumn<string>(
                name: "ModuleSlug",
                table: "devices",
                type: "character varying(50)",
                maxLength: 50,
                nullable: false,
                defaultValue: "coliseu-speed");














            migrationBuilder.AddColumn<bool>(
                name: "AllowNegativeStock",
                table: "companies",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "PriceTableMode",
                table: "companies",
                type: "text",
                nullable: false,
                defaultValue: "");









            migrationBuilder.AddColumn<string>(
                name: "AdminEmail",
                table: "audit_logs",
                type: "character varying(200)",
                maxLength: 200,
                nullable: true);










            migrationBuilder.AddColumn<string>(
                name: "Name",
                table: "admin_users",
                type: "character varying(200)",
                maxLength: 200,
                nullable: true);

            migrationBuilder.AddColumn<Guid>(
                name: "PermissionGroupId",
                table: "admin_users",
                type: "uuid",
                nullable: true);

            migrationBuilder.CreateTable(
                name: "branches",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    CompanyId = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: false),
                    Cnpj = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: true),
                    ErpEmpresaId = table.Column<int>(type: "integer", nullable: false),
                    ErpDeptoPadrao = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                    ErpCentroPadrao = table.Column<int>(type: "integer", nullable: false, defaultValue: 0),
                    IsDefault = table.Column<bool>(type: "boolean", nullable: false, defaultValue: false),
                    Status = table.Column<int>(type: "integer", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_branches", x => x.Id);
                    table.ForeignKey(
                        name: "FK_branches_companies_CompanyId",
                        column: x => x.CompanyId,
                        principalTable: "companies",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "company_modules",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    CompanyId = table.Column<Guid>(type: "uuid", nullable: false),
                    ModuleSlug = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    ApiKeyHash = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    DeviceLimit = table.Column<int>(type: "integer", nullable: false),
                    IsActive = table.Column<bool>(type: "boolean", nullable: false, defaultValue: true),
                    MiddlewareBaseUrl = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_company_modules", x => x.Id);
                    table.ForeignKey(
                        name: "FK_company_modules_companies_CompanyId",
                        column: x => x.CompanyId,
                        principalTable: "companies",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "permission_groups",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    Name = table.Column<string>(type: "character varying(200)", maxLength: 200, nullable: false),
                    Description = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    Permissions = table.Column<string>(type: "jsonb", nullable: false),
                    CreatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAt = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_permission_groups", x => x.Id);
                });

            migrationBuilder.CreateIndex(
                name: "IX_devices_DeviceUuid_CompanyId_Module",
                table: "devices",
                columns: new[] { "DeviceUuid", "CompanyId", "ModuleSlug" },
                filter: "\"DeviceUuid\" IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "IX_devices_ModuleSlug",
                table: "devices",
                column: "ModuleSlug");

            migrationBuilder.CreateIndex(
                name: "IX_audit_logs_AdminEmail",
                table: "audit_logs",
                column: "AdminEmail");

            migrationBuilder.CreateIndex(
                name: "IX_admin_users_PermissionGroupId",
                table: "admin_users",
                column: "PermissionGroupId");

            migrationBuilder.CreateIndex(
                name: "IX_branches_CompanyId_ErpEmpresaId",
                table: "branches",
                columns: new[] { "CompanyId", "ErpEmpresaId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_branches_DefaultBranch",
                table: "branches",
                column: "CompanyId",
                unique: true,
                filter: "\"IsDefault\" = true");

            migrationBuilder.CreateIndex(
                name: "IX_company_modules_ApiKeyHash",
                table: "company_modules",
                column: "ApiKeyHash");

            migrationBuilder.CreateIndex(
                name: "IX_company_modules_CompanyId_ModuleSlug",
                table: "company_modules",
                columns: new[] { "CompanyId", "ModuleSlug" },
                unique: true);

            migrationBuilder.AddForeignKey(
                name: "FK_admin_users_permission_groups_PermissionGroupId",
                table: "admin_users",
                column: "PermissionGroupId",
                principalTable: "permission_groups",
                principalColumn: "Id",
                onDelete: ReferentialAction.SetNull);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_admin_users_permission_groups_PermissionGroupId",
                table: "admin_users");

            migrationBuilder.DropTable(
                name: "branches");

            migrationBuilder.DropTable(
                name: "company_modules");

            migrationBuilder.DropTable(
                name: "permission_groups");

            migrationBuilder.DropIndex(
                name: "IX_devices_DeviceUuid_CompanyId_Module",
                table: "devices");

            migrationBuilder.DropIndex(
                name: "IX_devices_ModuleSlug",
                table: "devices");

            migrationBuilder.DropIndex(
                name: "IX_audit_logs_AdminEmail",
                table: "audit_logs");

            migrationBuilder.DropIndex(
                name: "IX_admin_users_PermissionGroupId",
                table: "admin_users");

            migrationBuilder.DropColumn(
                name: "ModuleSlug",
                table: "devices");

            migrationBuilder.DropColumn(
                name: "AllowNegativeStock",
                table: "companies");

            migrationBuilder.DropColumn(
                name: "PriceTableMode",
                table: "companies");

            migrationBuilder.DropColumn(
                name: "AdminEmail",
                table: "audit_logs");

            migrationBuilder.DropColumn(
                name: "Name",
                table: "admin_users");

            migrationBuilder.DropColumn(
                name: "PermissionGroupId",
                table: "admin_users");















































            migrationBuilder.CreateIndex(
                name: "IX_devices_DeviceUuid_CompanyId",
                table: "devices",
                columns: new[] { "DeviceUuid", "CompanyId" },
                unique: true);
        }
    }
}
