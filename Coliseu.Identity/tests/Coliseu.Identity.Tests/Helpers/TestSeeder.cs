using Coliseu.Identity.Application.Services;
using Coliseu.Identity.Domain.Entities;
using Coliseu.Identity.Infrastructure.Persistence;

namespace Coliseu.Identity.Tests.Helpers;

/// <summary>
/// Popula o banco de testes in-memory com dados de referência.
/// Todos os dados são fictícios — sem qualquer dado real de produção.
/// </summary>
public static class TestSeeder
{
    public const string TestCompanyKey    = "COLISEU-TEST-COMPANY-KEY-0000";
    public const string TestActivationKey = "TEST-0001"; // ≤ 10 chars (Domain rule)
    public const string TestDeviceUuid    = "TEST-DEVICE-UUID-001";

    /// <summary>
    /// Semeador: empresa ativa + dispositivo ativo.
    /// Idempotente — não insere se já existir dado.
    /// Retorna os IDs gerados para uso nos testes.
    /// </summary>
    public static async Task<(Guid CompanyId, Guid DeviceId)> SeedAsync(
        IdentityDbContext db,
        ICompanyKeyGenerator keyGen,
        IEncryptionService encryption)
    {
        if (db.Companies.Any())
        {
            var existing = db.Companies.First();
            var existingDevice = db.Devices.First();
            return (existing.Id, existingDevice.Id);
        }

        // 1. Empresa de teste com credenciais Firebird fictícias (encriptadas)
        var keyHash = keyGen.HashKey(TestCompanyKey);
        var encPwd  = encryption.Encrypt("masterkey");

        var company = Company.Create(
            name:                     "Empresa Teste",
            companyKeyHash:           keyHash,
            firebirdHost:             "localhost",
            firebirdDatabasePath:     "C:\\test\\db.fdb",
            firebirdUser:             "SYSDBA",
            firebirdPasswordEncrypted: encPwd,
            deviceLimit:              10,
            contactEmail:             "teste@coliseu.local");

        db.Companies.Add(company);
        await db.SaveChangesAsync();

        // 2. Dispositivo ativo (CreatePending → LinkHardware ativa o device)
        var device = Device.CreatePending(company.Id, TestActivationKey);
        device.LinkHardware(TestDeviceUuid, "Test Model", "Android 14", "1.0.0-test");
        db.Devices.Add(device);
        await db.SaveChangesAsync();

        return (company.Id, device.Id);
    }
}
