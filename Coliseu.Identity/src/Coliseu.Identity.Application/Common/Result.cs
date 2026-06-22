namespace Coliseu.Identity.Application.Common;

/// <summary>
/// Result pattern — alternativa a exceções para fluxo de controle.
/// Encapsula sucesso ou falha com mensagem de erro.
/// </summary>
public sealed class Result<T>
{
    public bool IsSuccess { get; }
    public T? Value { get; }
    public string? Error { get; }
    public int? StatusCode { get; }

    private Result(T value)
    {
        IsSuccess = true;
        Value = value;
    }

    private Result(string error, int statusCode = 400)
    {
        IsSuccess = false;
        Error = error;
        StatusCode = statusCode;
    }

    public static Result<T> Success(T value) => new(value);
    public static Result<T> Failure(string error, int statusCode = 400) => new(error, statusCode);
    public static Result<T> BadRequest(string error) => new(error, 400);
    public static Result<T> NotFound(string error) => new(error, 404);
    public static Result<T> Forbidden(string error) => new(error, 403);
    public static Result<T> TooManyRequests(string error) => new(error, 429);
}

/// <summary>Resultado paginado para listagens.</summary>
public sealed record PagedResult<T>(
    List<T> Items,
    int TotalCount,
    int Page,
    int PageSize)
{
    public int TotalPages => (int)Math.Ceiling(TotalCount / (double)PageSize);
    public bool HasNext => Page < TotalPages;
    public bool HasPrevious => Page > 1;
}
