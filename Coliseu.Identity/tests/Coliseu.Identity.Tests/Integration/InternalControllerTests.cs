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
/// Testes de integração do endpoint GET /internal/companies/{id}/firebird-config.
///
/// Protegido por Internal-API-Key header.
/// Cobertura:
///   ✅ API Key válida + empresa existente → 200 + credenciais
///   ✅ Sem API Key → 401
///   ✅ API Key incorreta → 401
///   ✅ ID inexistente → 404
/// </summary>
public sealed class InternalControllerTests : IAsyncLifetime
{
    private readonly IdentityWebFactory _factory = new();
    private HttpClient _client = null!;
    private Guid _companyId;

    public async Task InitializeAsync()
    {
        _client = await _factory.GetClientAsync();
        using var scope = _factory.Services.CreateScope();
        var (cid, _) = await TestSeeder.SeedAsync(
            scope.ServiceProvider.GetRequiredService<IdentityDbContext>(),
            scope.ServiceProvider.GetRequiredService<ICompanyKeyGenerator>(),
            scope.ServiceProvider.GetRequiredService<IEncryptionService>());
        _companyId = cid;
    }

    public Task DisposeAsync() { _factory.Dispose(); return Task.CompletedTask; }

    [Fact(DisplayName = "Internal: API Key válida + empresa existente → 200 + credenciais Firebird")]
    public async Task GetFirebirdConfig_ValidKey_ReturnsCredentials()
    {
        var request = new HttpRequestMessage(
            HttpMethod.Get,
            $"/internal/companies/{_companyId}/firebird-config");
        request.Headers.Add("X-Internal-Api-Key", IdentityWebFactory.TestInternalApiKey);

        var response = await _client.SendAsync(request);

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<FirebirdConfigResponse>();
        Assert.NotNull(body);
        Assert.Equal("localhost", body.Host);
        Assert.False(string.IsNullOrWhiteSpace(body.Password));
    }

    [Fact(DisplayName = "Internal: sem API Key → 401 Unauthorized")]
    public async Task GetFirebirdConfig_NoApiKey_ReturnsUnauthorized()
    {
        var response = await _client.GetAsync($"/internal/companies/{_companyId}/firebird-config");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact(DisplayName = "Internal: API Key errada → 401 Unauthorized")]
    public async Task GetFirebirdConfig_WrongApiKey_ReturnsUnauthorized()
    {
        var request = new HttpRequestMessage(
            HttpMethod.Get,
            $"/internal/companies/{_companyId}/firebird-config");
        request.Headers.Add("Internal-API-Key", "CHAVE-COMPLETAMENTE-ERRADA");

        var response = await _client.SendAsync(request);
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact(DisplayName = "Internal: ID inexistente + API Key válida → 404 Not Found")]
    public async Task GetFirebirdConfig_NonExistentCompany_ReturnsNotFound()
    {
        var request = new HttpRequestMessage(
            HttpMethod.Get,
            $"/internal/companies/{Guid.NewGuid()}/firebird-config");
        request.Headers.Add("X-Internal-Api-Key", IdentityWebFactory.TestInternalApiKey);

        var response = await _client.SendAsync(request);
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    private sealed record FirebirdConfigResponse(
        string? Host, string? Database, string? User, string? Password);
}
