using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace Coliseu.Identity.Infrastructure.Persistence.Migrations
{
    /// <inheritdoc />
    public partial class AddDeviceActivationKey : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            // Esta migration foi originalmente gerada para SQLite e tentava converter todos os
            // tipos de coluna (uuid→TEXT, timestamp→TEXT, boolean→INTEGER). Em PostgreSQL esse
            // conjunto de conversões quebra as foreign-keys e os defaults.
            //
            // O único objetivo real desta migration é adicionar a coluna ActivationKey.
            // As demais conversões de tipo são idempotentes no contexto PostgreSQL puro
            // (o InitialCreate já criou as colunas no tipo correto) e foram removidas.

            migrationBuilder.AddColumn<string>(
                name: "ActivationKey",
                table: "devices",
                type: "TEXT",
                maxLength: 10,
                nullable: false,
                defaultValue: "");

            migrationBuilder.CreateIndex(
                name: "IX_devices_ActivationKey",
                table: "devices",
                column: "ActivationKey",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_devices_ActivationKey",
                table: "devices");

            migrationBuilder.DropColumn(
                name: "ActivationKey",
                table: "devices");
        }
    }
}
