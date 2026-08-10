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
    public record AutoCenterVehicleDto(
        [property: JsonPropertyName("id_cliente")] int? IdCliente,
        [property: JsonPropertyName("id_veiculo")] int? IdVeiculo,
        [property: JsonPropertyName("brand")] string Brand,
        [property: JsonPropertyName("model")] string Model,
        [property: JsonPropertyName("plate")] string Plate,
        [property: JsonPropertyName("ano_fabrica")] int? AnoFabrica,
        [property: JsonPropertyName("ano_modelo")] int? AnoModelo,
        [property: JsonPropertyName("cor")] string Cor,
        [property: JsonPropertyName("obs")] string Obs,
        [property: JsonPropertyName("numero")] string Numero,
        [property: JsonPropertyName("numero_chassi")] string NumeroChassi,
        [property: JsonPropertyName("id_seguradora")] int? IdSeguradora,
        [property: JsonPropertyName("status")] int? Status,
        [property: JsonPropertyName("numero_1")] string Numero1,
        [property: JsonPropertyName("numero_2")] string Numero2,
        [property: JsonPropertyName("combustivel")] string Combustivel
    );

    public sealed class SyncAutoCenterVehiclesJob
    {
        private readonly FirebirdService _firebird;
        private readonly IHttpClientFactory _httpClientFactory;
        private readonly ILogger<SyncAutoCenterVehiclesJob> _logger;
        private readonly StatusStore _status;
        private readonly SemaphoreSlim _lock = new(1, 1);

        public SyncAutoCenterVehiclesJob(
            FirebirdService firebird,
            IHttpClientFactory httpClientFactory,
            ILogger<SyncAutoCenterVehiclesJob> logger,
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
                _logger.LogInformation("[AutoCenterVehicleSync] Buscando veículos no Firebird...");
                var rows = await _firebird.QueryAsync(@"
                    SELECT
                        ID_CLIENTE    AS id_cliente,
                        ID_VEICULO    AS id_veiculo,
                        MARCA         AS brand,
                        MODELO        AS model,
                        PLACA         AS plate,
                        ANO_FABRICA   AS ano_fabrica,
                        ANO_MODELO    AS ano_modelo,
                        COR           AS cor,
                        OBS           AS obs,
                        NUMERO        AS numero,
                        NUMERO_CHASSI AS numero_chassi,
                        ID_SEGURADORA AS id_seguradora,
                        STATUS        AS status,
                        NUMERO1       AS numero_1,
                        NUMERO2       AS numero_2,
                        COMBUSTIVEL   AS combustivel
                    FROM CLIENTES_VEICULOS
                    WHERE PLACA IS NOT NULL AND TRIM(PLACA) <> ''", ct: ct);

                if (rows.Count == 0)
                {
                    _logger.LogWarning("[AutoCenterVehicleSync] Nenhum veículo encontrado no Firebird.");
                    _status.Update("AutoCenter_Vehicles", 0, DateTime.Now, "Tabela vazia");
                    return;
                }

                var vehicles = new List<AutoCenterVehicleDto>();
                foreach (var r in rows)
                {
                    try
                    {
                        int.TryParse(r.GetValueOrDefault("id_cliente")?.ToString(), out var idCliente);
                        int.TryParse(r.GetValueOrDefault("id_veiculo")?.ToString(), out var idVeiculo);
                        int.TryParse(r.GetValueOrDefault("ano_fabrica")?.ToString(), out var anoFabrica);
                        int.TryParse(r.GetValueOrDefault("ano_modelo")?.ToString(), out var anoModelo);
                        int.TryParse(r.GetValueOrDefault("id_seguradora")?.ToString(), out var idSeguradora);
                        int.TryParse(r.GetValueOrDefault("status")?.ToString(), out var statusVal);

                        var brand = r.GetValueOrDefault("brand")?.ToString() ?? "";
                        var model = r.GetValueOrDefault("model")?.ToString() ?? "";
                        var plate = r.GetValueOrDefault("plate")?.ToString() ?? "";
                        var cor = r.GetValueOrDefault("cor")?.ToString() ?? "";
                        var obs = r.GetValueOrDefault("obs")?.ToString() ?? "";
                        var numero = r.GetValueOrDefault("numero")?.ToString() ?? "";
                        var chassi = r.GetValueOrDefault("numero_chassi")?.ToString() ?? "";
                        var num1 = r.GetValueOrDefault("numero_1")?.ToString() ?? "";
                        var num2 = r.GetValueOrDefault("numero_2")?.ToString() ?? "";
                        var combustivel = r.GetValueOrDefault("combustivel")?.ToString() ?? "";

                        vehicles.Add(new AutoCenterVehicleDto(
                            idCliente > 0 ? idCliente : null,
                            idVeiculo > 0 ? idVeiculo : null,
                            brand.Trim(),
                            model.Trim(),
                            plate.Trim(),
                            anoFabrica > 0 ? anoFabrica : null,
                            anoModelo > 0 ? anoModelo : null,
                            cor.Trim(),
                            obs.Trim(),
                            numero.Trim(),
                            chassi.Trim(),
                            idSeguradora > 0 ? idSeguradora : null,
                            statusVal,
                            num1.Trim(),
                            num2.Trim(),
                            combustivel.Trim()
                        ));
                    }
                    catch (Exception ex)
                    {
                        _logger.LogError(ex, "[AutoCenterVehicleSync] Erro ao converter linha do Firebird.");
                    }
                }

                if (vehicles.Count == 0) return;

                _logger.LogInformation("[AutoCenterVehicleSync] Enviando {Count} veículos para a VPS...", vehicles.Count);

                var httpClient = _httpClientFactory.CreateClient("AutoCenterApiClient");
                var response = await httpClient.PostAsJsonAsync("/internal/vehicles/sync", vehicles, ct);

                if (response.IsSuccessStatusCode)
                {
                    _logger.LogInformation("[AutoCenterVehicleSync] Sincronização concluída com sucesso!");
                    _status.Update("AutoCenter_Vehicles", vehicles.Count, DateTime.Now, "Sucesso");
                }
                else
                {
                    var errBody = await response.Content.ReadAsStringAsync(ct);
                    _logger.LogError("[AutoCenterVehicleSync] Falha ao enviar dados para VPS: {Code} - {Body}", response.StatusCode, errBody);
                    _status.Update("AutoCenter_Vehicles", 0, DateTime.Now, $"Erro API: {response.StatusCode}");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "[AutoCenterVehicleSync] Falha crítica na rotina.");
                _status.Update("AutoCenter_Vehicles", 0, DateTime.Now, $"Erro: {ex.Message}");
            }
            finally
            {
                _lock.Release();
            }
        }
    }
}
