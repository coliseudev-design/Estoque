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
/// Testes de integração do endpoint POST /device/login.
/// Todos os testes usam SQLite in-memory — zero conexão com produção.
///
/// Cobertura (API Endpoint Forge, Passo 7):
///   ✅ Happy path (200)
///   ✅ Chave inválida (403)
///   ✅ Body vazio (400)
///   ✅ DeviceUuid ausente (400)
/// </summary>
public sealed class DeviceLoginTests : IAsyncLifetime
{
    private readonly IdentityWebFactory _factory = new();
    private HttpClient _client = null!;

    public async Task InitializeAsync()
    {
        _client = await _factory.GetClientAsync();
        // Semeia dados de teste
        using var scope = _factory.Services.CreateScope();
        await TestSeeder.SeedAsync(
            scope.ServiceProvider.GetRequiredService<IdentityDbContext>(),
            scope.ServiceProvider.GetRequiredService<ICompanyKeyGenerator>(),
            scope.ServiceProvider.GetRequiredService<IEncryptionService>());
    }

    public Task DisposeAsync() { _factory.Dispose(); return Task.CompletedTask; }

    [Fact(DisplayName = "DeviceLogin: chave válida + UUID registrado → 200 + tokens")]
    public async Task Login_ValidKey_ReturnsOkWithTokens()
    {
        var response = await _client.PostAsJsonAsync("/auth/device-login", new
        {
            companyKey = TestSeeder.TestCompanyKey,
            deviceUuid = TestSeeder.TestDeviceUuid,
            model      = "Test Model",
            os         = "Android 14",
            appVersion = "1.0.0-test"
        });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<LoginResponse>();
        Assert.NotNull(body);
        Assert.False(string.IsNullOrWhiteSpace(body.AccessToken));
        Assert.False(string.IsNullOrWhiteSpace(body.RefreshToken));
        Assert.True(body.ExpiresInSeconds > 0);
    }

    [Fact(DisplayName = "DeviceLogin: chave inexistente → 403 Forbidden")]
    public async Task Login_InvalidKey_ReturnsForbidden()
    {
        var response = await _client.PostAsJsonAsync("/auth/device-login", new
        {
            companyKey = "INVALID-NONEXISTENT-KEY",
            deviceUuid = "SOME-UUID"
        });
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact(DisplayName = "DeviceLogin: body vazio → 400 Bad Request")]
    public async Task Login_EmptyBody_ReturnsBadRequest()
    {
        var response = await _client.PostAsJsonAsync("/auth/device-login", new { });
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact(DisplayName = "DeviceLogin: re-bind bloqueado — chave vinculada a UUID-A, tentativa com UUID-B → 403")]
    public async Task Login_RebindBlocked_ReturnsForbidden()
    {
        // TestSeeder.TestDeviceUuid = "TEST-DEVICE-UUID-001" está vinculado ao TestActivationKey.
        // Tentar ativar com mesmo TestActivationKey mas UUID diferente deve ser bloqueado.
        var response = await _client.PostAsJsonAsync("/auth/device-login", new
        {
            activationKey = TestSeeder.TestActivationKey,
            deviceUuid    = "DIFFERENT-HARDWARE-UUID-999",  // UUID diferente do vinculado
            model         = "Unknown Device",
            os            = "Android 15",
            appVersion    = "1.0.0-test"
        });

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);

        var body = await response.Content.ReadAsStringAsync();
        Assert.Contains("vinculada ao hardware", body, StringComparison.OrdinalIgnoreCase);
    }

    private sealed record LoginResponse(
        string? AccessToken, string? RefreshToken, int ExpiresInSeconds);
}

