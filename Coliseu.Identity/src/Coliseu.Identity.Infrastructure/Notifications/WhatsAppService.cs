using Coliseu.Identity.Application.Services;
using Coliseu.Identity.Domain.Entities;
using System.Net.Http;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Coliseu.Identity.Infrastructure.Notifications;

/// <summary>
/// Implementação do serviço de notificações de WhatsApp integrado com a UAZAPI.
/// </summary>
public sealed class WhatsAppService : IWhatsAppService
{
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly ILogger<WhatsAppService> _logger;
    private readonly WhatsAppOptions _options;

    public WhatsAppService(
        IHttpClientFactory httpClientFactory,
        ILogger<WhatsAppService> logger,
        IOptions<WhatsAppOptions> options)
    {
        _httpClientFactory = httpClientFactory;
        _logger = logger;
        _options = options.Value;
    }

    /// <inheritdoc />
    public async Task<bool> SendTextAsync(string phone, string message, CancellationToken ct = default)
    {
        if (!_options.Enabled)
        {
            _logger.LogInformation("[📲 WHATSAPP] Integração desabilitada nas configurações. Mensagem não enviada.");
            return false;
        }

        if (string.IsNullOrWhiteSpace(_options.ServerUrl) || string.IsNullOrWhiteSpace(_options.Token))
        {
            _logger.LogWarning("[📲 WHATSAPP] Servidor UAZAPI ou Token não configurados. Mensagem descartada.");
            return false;
        }

        var cleanPhone = FormatPhoneBrazil(phone);
        if (string.IsNullOrWhiteSpace(cleanPhone))
        {
            _logger.LogWarning("[📲 WHATSAPP] Número de telefone inválido: '{Phone}'", phone);
            return false;
        }

        try
        {
            using var client = _httpClientFactory.CreateClient();
            client.Timeout = TimeSpan.FromSeconds(10);

            // Garantir que a URL termina no padrão correto
            var baseUrl = _options.ServerUrl.TrimEnd('/');
            var url = $"{baseUrl}/send/text";

            var payload = new
            {
                number = cleanPhone,
                text = message,
                delay = 1200
            };

            var jsonPayload = JsonSerializer.Serialize(payload);
            using var request = new HttpRequestMessage(HttpMethod.Post, url);
            request.Headers.Add("token", _options.Token);
            request.Content = new StringContent(jsonPayload, Encoding.UTF8, "application/json");

            var response = await client.SendAsync(request, ct);
            var responseContent = await response.Content.ReadAsStringAsync(ct);

            if (response.IsSuccessStatusCode)
            {
                _logger.LogInformation("[📲 WHATSAPP] Mensagem enviada com sucesso para {Phone}. Resposta: {Resp}", cleanPhone, responseContent.Substring(0, Math.Min(80, responseContent.Length)));
                return true;
            }

            _logger.LogError("[📲 WHATSAPP] Erro ao enviar mensagem para {Phone}. Status: {Status}. Resposta: {Resp}", cleanPhone, response.StatusCode, responseContent);
            return false;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[📲 WHATSAPP] Exceção durante envio de mensagem de WhatsApp para {Phone}", cleanPhone);
            return false;
        }
    }

    /// <inheritdoc />
    public async Task NotifyRequestCreatedAsync(LicenseRequest request, CancellationToken ct = default)
    {
        // Notificar o Parceiro
        if (request.Partner != null && !string.IsNullOrWhiteSpace(request.Partner.Phone))
        {
            var modulesList = string.Join(", ", request.Modules.Select(m => $"{m.ModuleSlug} ({m.DeviceLimit} disp.)"));
            
            var partnerMessage = new StringBuilder();
            partnerMessage.AppendLine("📋 *Coliseu Sistemas — Servidor de Licenças*");
            partnerMessage.AppendLine();
            partnerMessage.AppendLine($"Olá, *{request.Partner.ContactName}*! 👋");
            partnerMessage.AppendLine();
            partnerMessage.AppendLine("Uma nova requisição de licença foi registrada com sucesso:");
            partnerMessage.AppendLine();
            partnerMessage.AppendLine($"🏢 *CNPJ do Cliente:* {request.ClientCnpj}");
            partnerMessage.AppendLine($"📝 *Tipo:* {request.ClientCompanyType}");
            partnerMessage.AppendLine($"📦 *Módulos:* {modulesList}");
            partnerMessage.AppendLine();
            partnerMessage.AppendLine($"📌 *Código da Requisição:* #{request.Id.ToString()[..8].ToUpper()}");
            partnerMessage.AppendLine();
            partnerMessage.AppendLine("Nossa equipe foi notificada e está revisando os dados para liberação.");

            // Disparar notificação de forma assíncrona (safe async)
            _ = SendTextAsync(request.Partner.Phone, partnerMessage.ToString(), ct)
                .ContinueWith(t => { if (t.IsFaulted) _logger.LogError(t.Exception, "[📲 WHATSAPP] Falha ao enviar notificação de criação para o parceiro."); }, ct);
        }

        // Notificar o Admin
        if (!string.IsNullOrWhiteSpace(_options.AdminPhone))
        {
            var modulesList = string.Join(", ", request.Modules.Select(m => $"{m.ModuleSlug} ({m.DeviceLimit} disp.)"));
            var partnerName = request.Partner?.Name ?? "Parceiro não identificado";

            var adminMessage = new StringBuilder();
            adminMessage.AppendLine("⚠️ *NOVA REQUISIÇÃO PENDENTE* ⚠️");
            adminMessage.AppendLine();
            adminMessage.AppendLine("Uma nova licença de módulo foi solicitada e aguarda aprovação:");
            adminMessage.AppendLine();
            adminMessage.AppendLine($"🤝 *Parceiro:* {partnerName}");
            adminMessage.AppendLine($"🏢 *CNPJ do Cliente:* {request.ClientCnpj}");
            adminMessage.AppendLine($"📝 *Tipo:* {request.ClientCompanyType}");
            adminMessage.AppendLine($"📦 *Módulos:* {modulesList}");
            adminMessage.AppendLine();
            adminMessage.AppendLine($"📌 *Código:* #{request.Id.ToString()[..8].ToUpper()}");
            adminMessage.AppendLine();
            adminMessage.AppendLine("Acesse o Painel Administrativo para aprovar ou recusar.");

            // Disparar notificação de forma assíncrona (safe async)
            _ = SendTextAsync(_options.AdminPhone, adminMessage.ToString(), ct)
                .ContinueWith(t => { if (t.IsFaulted) _logger.LogError(t.Exception, "[📲 WHATSAPP] Falha ao enviar notificação de criação para o administrador."); }, ct);
        }
    }

    /// <inheritdoc />
    public async Task NotifyRequestApprovedAsync(LicenseRequest request, string companyKey, CancellationToken ct = default)
    {
        if (request.Partner == null || string.IsNullOrWhiteSpace(request.Partner.Phone))
        {
            _logger.LogWarning("[📲 WHATSAPP] Parceiro ou número do parceiro não disponível para notificação de aprovação.");
            return;
        }

        var modulesList = string.Join(", ", request.Modules.Select(m => m.ModuleSlug));

        var partnerMessage = new StringBuilder();
        partnerMessage.AppendLine("🎉 *Coliseu Sistemas — Licença Aprovada!*");
        partnerMessage.AppendLine();
        partnerMessage.AppendLine($"Olá, *{request.Partner.ContactName}*! 👋");
        partnerMessage.AppendLine();
        partnerMessage.AppendLine($"A requisição de licença *#{request.Id.ToString()[..8].ToUpper()}* foi *APROVADA* ✅");
        partnerMessage.AppendLine();
        partnerMessage.AppendLine($"🏢 *CNPJ do Cliente:* {request.ClientCnpj}");
        partnerMessage.AppendLine($"📦 *Módulos Ativados:* {modulesList}");
        partnerMessage.AppendLine();
        partnerMessage.AppendLine("🔑 *CHAVE DE ATIVAÇÃO:*");
        partnerMessage.AppendLine($"`{companyKey}`");
        partnerMessage.AppendLine();
        partnerMessage.AppendLine("⚠️ *Importante:* Copie a chave de ativação acima e insira no aplicativo mobile do cliente para ativação imediata.");

        // Disparar notificação de forma assíncrona (safe async)
        _ = SendTextAsync(request.Partner.Phone, partnerMessage.ToString(), ct)
            .ContinueWith(t => { if (t.IsFaulted) _logger.LogError(t.Exception, "[📲 WHATSAPP] Falha ao enviar notificação de aprovação para o parceiro."); }, ct);
    }

    /// <inheritdoc />
    public async Task NotifyRequestRejectedAsync(LicenseRequest request, string reason, CancellationToken ct = default)
    {
        if (request.Partner == null || string.IsNullOrWhiteSpace(request.Partner.Phone))
        {
            _logger.LogWarning("[📲 WHATSAPP] Parceiro ou número do parceiro não disponível para notificação de rejeição.");
            return;
        }

        var partnerMessage = new StringBuilder();
        partnerMessage.AppendLine("❌ *Coliseu Sistemas — Requisição Recusada*");
        partnerMessage.AppendLine();
        partnerMessage.AppendLine($"Olá, *{request.Partner.ContactName}*! 👋");
        partnerMessage.AppendLine();
        partnerMessage.AppendLine($"Lamentamos informar que a requisição *#{request.Id.ToString()[..8].ToUpper()}* para o CNPJ {request.ClientCnpj} foi *RECUSADA* pelo administrador.");
        partnerMessage.AppendLine();
        partnerMessage.AppendLine($"📝 *Motivo da Recusa:* {reason}");
        partnerMessage.AppendLine();
        partnerMessage.AppendLine("Se desejar revisar os dados ou tirar dúvidas, por favor entre em contato com nossa equipe.");

        // Disparar notificação de forma assíncrona (safe async)
        _ = SendTextAsync(request.Partner.Phone, partnerMessage.ToString(), ct)
            .ContinueWith(t => { if (t.IsFaulted) _logger.LogError(t.Exception, "[📲 WHATSAPP] Falha ao enviar notificação de rejeição para o parceiro."); }, ct);
    }

    /// <summary>
    /// Limpa e formata números de telefone brasileiros para o padrão UAZAPI (55 + DDD + Número sem o 9 extra de celular se necessário).
    /// </summary>
    private static string FormatPhoneBrazil(string phone)
    {
        if (string.IsNullOrWhiteSpace(phone)) return string.Empty;

        // Remove tudo o que não for número
        var cleaned = Regex.Replace(phone, @"\D", "");

        // Se o número tiver o sufixo @s.whatsapp.net do jid do WhatsApp, já terá sido limpo de letras pelo Regex acima.
        // No entanto, se o número for vazio após a limpeza, cancela
        if (cleaned.Length < 8) return string.Empty;

        // Se o número tem 13 dígitos e começa com 55 (ex: 5567999998888)
        if (cleaned.Length == 13 && cleaned.StartsWith("55"))
        {
            var ddd = cleaned.Substring(2, 2);
            var number = cleaned.Substring(5); // pula o 9 extra (posicionamento: 55 [2] DDD [2] 9 [1] NUM [8])
            cleaned = $"55{ddd}{number}";
        }
        // Se tem 11 dígitos (DDD + 9 + 8 dígitos) e não começa com 55, adiciona o 55 e remove o 9 extra
        else if (cleaned.Length == 11 && !cleaned.StartsWith("55"))
        {
            var ddd = cleaned.Substring(0, 2);
            var number = cleaned.Substring(3); // pula o 9 extra
            cleaned = $"55{ddd}{number}";
        }
        // Se tem 10 dígitos (DDD + 8 dígitos) e não começa com 55, apenas adiciona o 55
        else if (cleaned.Length == 10 && !cleaned.StartsWith("55"))
        {
            cleaned = "55" + cleaned;
        }
        // Se já começa com 55 e tem 12 dígitos (55 + DDD + 8 dígitos), está correto
        else if (cleaned.Length == 12 && !cleaned.StartsWith("55"))
        {
            cleaned = "55" + cleaned.Substring(2); // garante o prefixo 55
        }
        else if (!cleaned.StartsWith("55"))
        {
            cleaned = "55" + cleaned;
        }

        return cleaned;
    }
}
