using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using System.Threading.Tasks;
using ColiseuSales.Worker.Config;
using ColiseuSales.Worker.Services;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace ColiseuSales.Worker.Jobs
{
    public record AutoCenterCustomerDto(
        [property: JsonPropertyName("erpId")] int ErpId,
        [property: JsonPropertyName("name")] string Name,
        [property: JsonPropertyName("fantasyName")] string FantasyName,
        [property: JsonPropertyName("cpfCnpj")] string CpfCnpj,
        [property: JsonPropertyName("phone")] string Phone,
        [property: JsonPropertyName("phone2")] string Phone2,
        [property: JsonPropertyName("email")] string Email,
        [property: JsonPropertyName("city")] string City,
        [property: JsonPropertyName("address")] string Address,
        [property: JsonPropertyName("active")] bool Active
    );

    public sealed class SyncAutoCenterCustomersJob
    {
        private readonly FirebirdService _firebird;
        private readonly IHttpClientFactory _httpClientFactory;
        private readonly ILogger<SyncAutoCenterCustomersJob> _logger;
        private readonly StatusStore _status;
        private readonly SemaphoreSlim _lock = new(1, 1);

        public SyncAutoCenterCustomersJob(
            FirebirdService firebird,
            IHttpClientFactory httpClientFactory,
            ILogger<SyncAutoCenterCustomersJob> logger,
            StatusStore status)
        {
            _firebird = firebird;
            _httpClientFactory = httpClientFactory;
            _logger = logger;
            _status = status;
        }

        public async Task RunAsync(CancellationToken ct = default)
        {
            if (!await _lock.WaitAsync(0, ct))
            {
                return;
            }

            try
            {
                _logger.LogInformation("[AutoCenterCustomerSync] Buscando clientes no Firebird...");
                var rows = await _firebird.QueryAsync(@"
                    SELECT
                        C.ID_CLIENTE    AS id,
                        C.NOME          AS name,
                        C.NOME_FANTASIA AS tradeName,
                        C.CPF_CNPJ      AS cnpj,
                        C.FONE_RES      AS phone,
                        C.CELULAR       AS mobile,
                        C.EMAIL         AS email,
                        C.ENDERECO_FULL AS street,
                        C.CIDADE        AS city,
                        C.CLASSIFICACAO_DESC AS status
                    FROM MOB_LISTACLIENTES C
                    ORDER BY C.NOME", ct: ct);

                if (rows.Count == 0)
                {
                    _logger.LogWarning("[AutoCenterCustomerSync] Nenhum cliente encontrado na view MOB_LISTACLIENTES.");
                    _status.Update("AutoCenter_Customers", 0, DateTime.Now, "View vazia");
                    return;
                }

                var customers = new List<AutoCenterCustomerDto>();
                foreach (var r in rows)
                {
                    try
                    {
                        int.TryParse(r.GetValueOrDefault("id")?.ToString(), out var erpId);
                        if (erpId == 0) continue;

                        var name = r.GetValueOrDefault("name")?.ToString() ?? "";
                        var fantasyName = r.GetValueOrDefault("tradeName")?.ToString() ?? "";
                        var cpfCnpj = r.GetValueOrDefault("cnpj")?.ToString() ?? "";
                        var phone = r.GetValueOrDefault("phone")?.ToString() ?? "";
                        var phone2 = r.GetValueOrDefault("mobile")?.ToString() ?? "";
                        var email = r.GetValueOrDefault("email")?.ToString() ?? "";
                        var city = r.GetValueOrDefault("city")?.ToString() ?? "";
                        var address = r.GetValueOrDefault("street")?.ToString() ?? "";
                        var status = r.GetValueOrDefault("status")?.ToString() ?? "";
                        bool active = !string.Equals(status, "INATIVO", StringComparison.OrdinalIgnoreCase);

                        customers.Add(new AutoCenterCustomerDto(
                             erpId,
                             name,
                             fantasyName,
                             cpfCnpj,
                             phone,
                             phone2,
                             email,
                             city,
                             address,
                             active
                        ));
                    }
                    catch (Exception ex)
                    {
                        _logger.LogWarning("[AutoCenterCustomerSync] Erro ao mapear linha de cliente: {Err}", ex.Message);
                    }
                }

                if (customers.Count == 0)
                {
                    _status.Update("AutoCenter_Customers", 0, DateTime.Now, "Zero clientes válidos");
                    return;
                }

                _logger.LogInformation("[AutoCenterCustomerSync] Enviando {Count} clientes para o AutoCenter Middleware...", customers.Count);
                
                var client = _httpClientFactory.CreateClient("AutoCenterApiClient");
                
                // Realiza POST para /internal/customers/sync
                var res = await client.PostAsJsonAsync("/internal/customers/sync", customers, ct);

                if (res.IsSuccessStatusCode)
                {
                    _logger.LogInformation("[AutoCenterCustomerSync] Sincronização concluída com sucesso. {Count} clientes enviados.", customers.Count);
                    _status.AppendLog($"[{DateTime.Now:HH:mm:ss}] ✓ [AutoCenter] Clientes Sincronizados: {customers.Count}");
                    _status.Update("AutoCenter_Customers", customers.Count, DateTime.Now);
                }
                else
                {
                    var body = await res.Content.ReadAsStringAsync(ct);
                    _logger.LogError("[AutoCenterCustomerSync] Falha ao enviar para o middleware: {Status} | {Body}", res.StatusCode, body);
                    _status.Update("AutoCenter_Customers", 0, DateTime.Now, $"HTTP {(int)res.StatusCode}");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError("[AutoCenterCustomerSync] Erro crítico no Sync de Clientes: {Err}", ex.Message);
                _status.Update("AutoCenter_Customers", 0, DateTime.Now, ex.Message);
            }
            finally
            {
                _lock.Release();
            }
        }
    }
}
