using Coliseu.Identity.Domain.Entities;

namespace Coliseu.Identity.Application.Services;

/// <summary>
/// Serviço para envio de notificações via WhatsApp (UAZAPI).
/// </summary>
public interface IWhatsAppService
{
    /// <summary>
    /// Envia uma mensagem de texto simples para um número de telefone.
    /// </summary>
    Task<bool> SendTextAsync(string phone, string message, CancellationToken ct = default);

    /// <summary>
    /// Notifica o parceiro (confirmação) e o administrador (solicitação pendente) de uma nova requisição.
    /// </summary>
    Task NotifyRequestCreatedAsync(LicenseRequest request, CancellationToken ct = default);

    /// <summary>
    /// Notifica o parceiro sobre a aprovação da requisição com a chave da empresa criada.
    /// </summary>
    Task NotifyRequestApprovedAsync(LicenseRequest request, string companyKey, CancellationToken ct = default);

    /// <summary>
    /// Notifica o parceiro sobre a rejeição da requisição com a respectiva justificativa.
    /// </summary>
    Task NotifyRequestRejectedAsync(LicenseRequest request, string reason, CancellationToken ct = default);
}
