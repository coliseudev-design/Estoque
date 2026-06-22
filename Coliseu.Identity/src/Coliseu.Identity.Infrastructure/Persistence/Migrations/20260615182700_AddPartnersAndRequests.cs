using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Coliseu.Identity.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddPartnersAndRequests : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "partners",
                columns: table => new
                {
                    Id = table.Column<Guid>(nullable: false),
                    Name = table.Column<string>(maxLength: 200, nullable: false),
                    Cnpj = table.Column<string>(maxLength: 20, nullable: false),
                    ContactName = table.Column<string>(maxLength: 150, nullable: false),
                    Email = table.Column<string>(maxLength: 255, nullable: false),
                    Phone = table.Column<string>(maxLength: 50, nullable: false),
                    CreatedAt = table.Column<DateTime>(nullable: false),
                    UpdatedAt = table.Column<DateTime>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_partners", x => x.Id);
                });

            migrationBuilder.CreateTable(
                name: "license_requests",
                columns: table => new
                {
                    Id = table.Column<Guid>(nullable: false),
                    PartnerId = table.Column<Guid>(nullable: false),
                    CompanyName = table.Column<string>(maxLength: 200, nullable: false),
                    ClientCnpj = table.Column<string>(maxLength: 20, nullable: false),
                    ClientCompanyType = table.Column<string>(maxLength: 50, nullable: false),
                    CostCenterCode = table.Column<string>(maxLength: 50, nullable: true),
                    DeptCode = table.Column<string>(maxLength: 50, nullable: true),
                    PriceTableMode = table.Column<string>(maxLength: 50, nullable: false, defaultValue: "none"),
                    AllowNegativeStock = table.Column<bool>(nullable: false, defaultValue: false),
                    FirebirdHost = table.Column<string>(maxLength: 255, nullable: false),
                    FirebirdDatabasePath = table.Column<string>(maxLength: 500, nullable: false),
                    FirebirdUser = table.Column<string>(maxLength: 100, nullable: false),
                    FirebirdPasswordEncrypted = table.Column<string>(maxLength: 500, nullable: false),
                    Notes = table.Column<string>(maxLength: 2000, nullable: true),
                    Status = table.Column<int>(nullable: false),
                    RequestedByAdminId = table.Column<Guid>(nullable: true),
                    RequestedAt = table.Column<DateTime>(nullable: false),
                    ReviewedByAdminId = table.Column<Guid>(nullable: true),
                    ReviewedAt = table.Column<DateTime>(nullable: true),
                    RejectReason = table.Column<string>(maxLength: 2000, nullable: true),
                    BranchesJson = table.Column<string>(nullable: true),
                    CompanyId = table.Column<Guid>(nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_license_requests", x => x.Id);
                    table.ForeignKey(
                        name: "FK_license_requests_companies_CompanyId",
                        column: x => x.CompanyId,
                        principalTable: "companies",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.SetNull);
                    table.ForeignKey(
                        name: "FK_license_requests_partners_PartnerId",
                        column: x => x.PartnerId,
                        principalTable: "partners",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "license_request_modules",
                columns: table => new
                {
                    Id = table.Column<Guid>(nullable: false),
                    LicenseRequestId = table.Column<Guid>(nullable: false),
                    ModuleSlug = table.Column<string>(maxLength: 50, nullable: false),
                    DeviceLimit = table.Column<int>(nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_license_request_modules", x => x.Id);
                    table.ForeignKey(
                        name: "FK_license_request_modules_license_requests_LicenseRequestId",
                        column: x => x.LicenseRequestId,
                        principalTable: "license_requests",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_license_request_modules_LicenseRequestId",
                table: "license_request_modules",
                column: "LicenseRequestId");

            migrationBuilder.CreateIndex(
                name: "IX_license_request_modules_LicenseRequestId_ModuleSlug",
                table: "license_request_modules",
                columns: new[] { "LicenseRequestId", "ModuleSlug" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_license_requests_ClientCnpj",
                table: "license_requests",
                column: "ClientCnpj");

            migrationBuilder.CreateIndex(
                name: "IX_license_requests_CompanyId",
                table: "license_requests",
                column: "CompanyId");

            migrationBuilder.CreateIndex(
                name: "IX_license_requests_PartnerId",
                table: "license_requests",
                column: "PartnerId");

            migrationBuilder.CreateIndex(
                name: "IX_license_requests_Status",
                table: "license_requests",
                column: "Status");

            migrationBuilder.CreateIndex(
                name: "IX_partners_Cnpj",
                table: "partners",
                column: "Cnpj",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_partners_Name",
                table: "partners",
                column: "Name");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "license_request_modules");

            migrationBuilder.DropTable(
                name: "license_requests");

            migrationBuilder.DropTable(
                name: "partners");
        }
    }
}
