namespace Coliseu.Identity.Domain.Enums;

/// <summary>
/// Status de processamento de uma requisição de licença no painel comercial.
/// </summary>
public enum RequestStatus
{
    /// <summary>Aguardando revisão.</summary>
    Pending = 0,

    /// <summary>Sendo processada/ativada no momento.</summary>
    InProgress = 1,

    /// <summary>Aprovada e empresa criada/ativada.</summary>
    Approved = 2,

    /// <summary>Recusada com justificativa.</summary>
    Rejected = 3
}
