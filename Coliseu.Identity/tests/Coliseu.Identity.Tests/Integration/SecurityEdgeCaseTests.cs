using System.Net;
using System.Net.Http.Json;
using Coliseu.Identity.Application.Services;
using Coliseu.Identity.Infrastructure.Persistence;
using Coliseu.Identity.Tests.Helpers;
using Coliseu.Identity.Tests.Infrastructure;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace Coliseu.Identity.Tests.Integration;

/// <summary>
/// Testes de edge cases de segurança do login de dispositivo.
///
/// Cenários críticos que DEVEM bloquear o acesso:
///   ✅ Dispositivo bloqueado → 403
///   ✅ Dispositivo revogado → 403
///   ✅ Empresa suspensa → 403
///   ✅ Empresa bloqueada → 403
/// </summary>
public sealed class SecurityEdgeCaseTests : IAsyncLifetime
{
    private readonly IdentityWebFactory _factory = new();
    private HttpClient _client = null!;

    public async Task InitializeAsync()
        => _client = await _factory.GetClientAsync();

    public Task DisposeAsync() { _factory.Dispose(); return Task.CompletedTask; }

    [Fact(DisplayName = "Security: dispositivo BLOQUEADO → 403 Forbidden")]
    public async Task Login_BlockedDevice_ReturnsForbidden()
    {
        // Arrange: semeia empresa ativa + device, depois bloqueia o device
        using var scope = _factory.Services.CreateScope();
        var db          = scope.ServiceProvider.GetRequiredService<IdentityDbContext>();
        var keyGen      = scope.ServiceProvider.GetRequiredService<ICompanyKeyGenerator>();
        var encryption  = scope.ServiceProvider.GetRequiredService<IEncryptionService>();
        await TestSeeder.SeedAsync(db, keyGen, encryption);

        // Bloqueia o device
        var device = db.Devices.First();
        device.Block();
        await db.SaveChangesAsync();

        // Act
        var response = await _client.PostAsJsonAsync("/auth/device-login", new
        {
            companyKey = TestSeeder.TestCompanyKey,
            deviceUuid = TestSeeder.TestDeviceUuid,
        });

        // Assert
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact(DisplayName = "Security: dispositivo REVOGADO → 403 Forbidden")]
    public async Task Login_RevokedDevice_ReturnsForbidden()
    {
        using var scope = _factory.Services.CreateScope();
        var db          = scope.ServiceProvider.GetRequiredService<IdentityDbContext>();
        var keyGen      = scope.ServiceProvider.GetRequiredService<ICompanyKeyGenerator>();
        var encryption  = scope.ServiceProvider.GetRequiredService<IEncryptionService>();
        await TestSeeder.SeedAsync(db, keyGen, encryption);

        // Revoga o device permanentemente
        var device = db.Devices.First();
        device.Revoke();
        await db.SaveChangesAsync();

        var response = await _client.PostAsJsonAsync("/auth/device-login", new
        {
            companyKey = TestSeeder.TestCompanyKey,
            deviceUuid = TestSeeder.TestDeviceUuid,
        });

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact(DisplayName = "Security: empresa SUSPENSA → 403 Forbidden")]
    public async Task Login_SuspendedCompany_ReturnsForbidden()
    {
        using var scope = _factory.Services.CreateScope();
        var db          = scope.ServiceProvider.GetRequiredService<IdentityDbContext>();
        var keyGen      = scope.ServiceProvider.GetRequiredService<ICompanyKeyGenerator>();
        var encryption  = scope.ServiceProvider.GetRequiredService<IEncryptionService>();
        await TestSeeder.SeedAsync(db, keyGen, encryption);

        // Suspende a empresa
        var company = db.Companies.First();
        company.Suspend();
        await db.SaveChangesAsync();

        var response = await _client.PostAsJsonAsync("/auth/device-login", new
        {
            companyKey = TestSeeder.TestCompanyKey,
            deviceUuid = TestSeeder.TestDeviceUuid,
        });

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact(DisplayName = "Security: empresa BLOQUEADA → 403 Forbidden")]
    public async Task Login_BlockedCompany_ReturnsForbidden()
    {
        using var scope = _factory.Services.CreateScope();
        var db          = scope.ServiceProvider.GetRequiredService<IdentityDbContext>();
        var keyGen      = scope.ServiceProvider.GetRequiredService<ICompanyKeyGenerator>();
        var encryption  = scope.ServiceProvider.GetRequiredService<IEncryptionService>();
        await TestSeeder.SeedAsync(db, keyGen, encryption);

        // Bloqueia a empresa
        var company = db.Companies.First();
        company.Block();
        await db.SaveChangesAsync();

        var response = await _client.PostAsJsonAsync("/auth/device-login", new
        {
            companyKey = TestSeeder.TestCompanyKey,
            deviceUuid = TestSeeder.TestDeviceUuid,
        });

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }
}
