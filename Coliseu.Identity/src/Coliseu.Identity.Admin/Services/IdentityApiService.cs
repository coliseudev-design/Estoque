using System.Net.Http.Headers;
using System.Text.Json;
using Blazored.LocalStorage;
using Coliseu.Identity.Application.Admin.DTOs;
using Coliseu.Identity.Application.Auth.DTOs;
using Coliseu.Identity.Application.Common;

namespace Coliseu.Identity.Admin.Services;

/// <summary>
/// Serviço de comunicação com a Coliseu.Identity API.
/// </summary>
public sealed class IdentityApiService
{
    private readonly HttpClient _http;
    private readonly ILocalStorageService _localStorage;

    public IdentityApiService(HttpClient http, ILocalStorageService localStorage)
    {
        _http = http;
        _localStorage = localStorage;
    }

    /// <summary>URL base do HttpClient para construir URLs de imagem.</summary>
    public string BaseUrl => _http.BaseAddress?.ToString() ?? string.Empty;

    // ── Auth ─────────────────────────────────────────────────────────────────

    public async Task<Result<AdminLoginResponse>> LoginAsync(AdminLoginRequest request)
    {
        var response = await _http.PostAsJsonAsync("admin/auth/login", request);
        return await HandleResponseAsync<AdminLoginResponse>(response);
    }

    // ── Companies ──────────────────────────────────────────────────────────

    public async Task<Result<PagedResult<CompanyDto>>> GetCompaniesAsync(int page = 1, int pageSize = 20)
    {
        await PrepareAuthHeader();
        var response = await _http.GetAsync($"admin/companies?page={page}&pageSize={pageSize}");
        return await HandleResponseAsync<PagedResult<CompanyDto>>(response);
    }

    public async Task<Result<CompanyDto>> GetCompanyAsync(Guid id)
    {
        await PrepareAuthHeader();
        var response = await _http.GetAsync($"admin/companies/{id}");
        return await HandleResponseAsync<CompanyDto>(response);
    }

    public async Task<Result<CreateCompanyResponse>> CreateCompanyAsync(CreateCompanyRequest request)
    {
        await PrepareAuthHeader();
        var response = await _http.PostAsJsonAsync("admin/companies", request);
        return await HandleResponseAsync<CreateCompanyResponse>(response);
    }

    public async Task<Result<CompanyDto>> UpdateCompanyAsync(Guid id, UpdateCompanyRequest request)
    {
        await PrepareAuthHeader();
        var response = await _http.PutAsJsonAsync($"admin/companies/{id}", request);
        return await HandleResponseAsync<CompanyDto>(response);
    }

    public async Task<Result<string>> UpdateCompanyStatusAsync(Guid id, string status)
    {
        await PrepareAuthHeader();
        var response = await _http.PatchAsJsonAsync($"admin/companies/{id}/status", new { status });
        var result = await HandleResponseAsync<dynamic>(response);
        return result.IsSuccess ? Result<string>.Success(status) : Result<string>.Failure(result.Error!, result.StatusCode ?? 500);
    }

    /// <summary>
    /// Re-gera a CompanyKey (API Key) da empresa.
    /// A nova chave é retornada em texto — deve ser salva imediatamente pelo admin.
    /// </summary>
    public async Task<Result<RotateKeyResponse>> RotateCompanyKeyAsync(Guid id)
    {
        await PrepareAuthHeader();
        var response = await _http.PostAsync($"admin/companies/{id}/rotate-key", null);
        return await HandleResponseAsync<RotateKeyResponse>(response);
    }

    /// <summary>Upload de logo da empresa (Base64-encoded).</summary>
    public async Task<Result<string>> UploadCompanyLogoAsync(Guid id, string logoBase64)
    {
        await PrepareAuthHeader();
        var response = await _http.PutAsJsonAsync($"admin/companies/{id}/logo", new { logoBase64 });
        var result = await HandleResponseAsync<dynamic>(response);
        return result.IsSuccess
            ? Result<string>.Success("Logo atualizada.")
            : Result<string>.Failure(result.Error!, result.StatusCode ?? 500);
    }

    /// <summary>Remove a logo da empresa.</summary>
    public async Task<Result<string>> DeleteCompanyLogoAsync(Guid id)
    {
        await PrepareAuthHeader();
        var response = await _http.DeleteAsync($"admin/companies/{id}/logo");
        var result = await HandleResponseAsync<dynamic>(response);
        return result.IsSuccess
            ? Result<string>.Success("Logo removida.")
            : Result<string>.Failure(result.Error!, result.StatusCode ?? 500);
    }

    // ── Devices ──────────────────────────────────────────────────────────────

    public async Task<Result<dynamic>> GetDevicesByCompanyAsync(Guid companyId)
    {
        await PrepareAuthHeader();
        var response = await _http.GetAsync($"admin/devices/by-company/{companyId}");
        return await HandleResponseAsync<dynamic>(response);
    }

    public async Task<Result<string>> UpdateDeviceStatusAsync(Guid id, string status)
    {
        await PrepareAuthHeader();
        var response = await _http.PatchAsJsonAsync($"admin/devices/{id}/status", new { status });
        var result = await HandleResponseAsync<dynamic>(response);
        return result.IsSuccess ? Result<string>.Success(status) : Result<string>.Failure(result.Error!, result.StatusCode ?? 500);
    }

    // ── Audit ────────────────────────────────────────────────────────────────

    public async Task<Result<PagedResult<AuditLogDto>>> GetAuditLogsAsync(int page = 1, int pageSize = 50)
    {
        await PrepareAuthHeader();
        var response = await _http.GetAsync($"admin/audit?page={page}&pageSize={pageSize}");
        return await HandleResponseAsync<PagedResult<AuditLogDto>>(response);
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private async Task PrepareAuthHeader()
    {
        var token = await _localStorage.GetItemAsync<string>("authToken");
        if (!string.IsNullOrEmpty(token))
        {
            _http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
        }
    }

    private static async Task<Result<T>> HandleResponseAsync<T>(HttpResponseMessage response)
    {
        if (response.IsSuccessStatusCode)
        {
            var data = await response.Content.ReadFromJsonAsync<T>();
            return Result<T>.Success(data!);
        }

        var errorObj = await response.Content.ReadFromJsonAsync<JsonElement>();
        var errorMsg = errorObj.TryGetProperty("error", out var e) ? e.GetString() : "Erro desconhecido.";
        return Result<T>.Failure(errorMsg ?? "Erro na API", (int)response.StatusCode);
    }
}
