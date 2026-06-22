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
/// Testes de integração do endpoint POST /device/refresh.
///
/// Fluxo: Login → Refresh → token antigo revogado (403).
/// </summary>
public sealed class RefreshTokenTests : IAsyncLifetime
{
    private readonly IdentityWebFactory _factory = new();
    private HttpClient _client = null!;

    public async Task InitializeAsync()
    {
        _client = await _factory.GetClientAsync();
        using var scope = _factory.Services.CreateScope();
        await TestSeeder.SeedAsync(
            scope.ServiceProvider.GetRequiredService<IdentityDbContext>(),
            scope.ServiceProvider.GetRequiredService<ICompanyKeyGenerator>(),
            scope.ServiceProvider.GetRequiredService<IEncryptionService>());
    }

    public Task DisposeAsync() { _factory.Dispose(); return Task.CompletedTask; }

    private async Task<string?> DoLoginAsync()
    {
        var res = await _client.PostAsJsonAsync("/auth/device-login", new
        {
            companyKey = TestSeeder.TestCompanyKey,
            deviceUuid = TestSeeder.TestDeviceUuid,
            model      = "Test Model",
            os         = "Android 14",
            appVersion = "1.0.0-test"
        });
        if (!res.IsSuccessStatusCode) return null;
        var body = await res.Content.ReadFromJsonAsync<TokenResponse>();
        return body?.RefreshToken;
    }

    [Fact(DisplayName = "Refresh: token válido → 200 + novos tokens (rotação)")]
    public async Task Refresh_ValidToken_ReturnsNewTokens()
    {
        var refreshToken = await DoLoginAsync();
        Assert.NotNull(refreshToken);

        var response = await _client.PostAsJsonAsync("/auth/refresh", new
        {
            refreshToken = refreshToken
        });

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<TokenResponse>();
        Assert.NotNull(body);
        Assert.False(string.IsNullOrWhiteSpace(body.AccessToken));
        Assert.NotEqual(refreshToken, body.RefreshToken); // Rotação: deve ser token NOVO
    }

    [Fact(DisplayName = "Refresh: token inválido → 403 Forbidden")]
    public async Task Refresh_InvalidToken_ReturnsForbidden()
    {
        var response = await _client.PostAsJsonAsync("/auth/refresh", new
        {
            refreshToken = "token-falso-nao-existe"
        });
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact(DisplayName = "Refresh: body vazio → 400 Bad Request")]
    public async Task Refresh_EmptyBody_ReturnsBadRequest()
    {
        var response = await _client.PostAsJsonAsync("/auth/refresh", new { });
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    private sealed record TokenResponse(
        string? AccessToken, string? RefreshToken, int ExpiresInSeconds);
}
