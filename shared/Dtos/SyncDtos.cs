using System.ComponentModel.DataAnnotations;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ColiseuSales.Shared.Dtos;

// ─────────────────────────────────────────────────────────────────────────────
// PUSH: Worker → API  (dados do ERP para a VPS)
// ─────────────────────────────────────────────────────────────────────────────

public sealed record ProductDto(
    [Required] string  Code,
    [Required] string  Name,
    string?  NameShort,
    decimal? Price,
    decimal? PriceMin,
    decimal  Stock,
    string?  Unit,
    string?  Brand,
    string?  BarCode,
    string?  Reference,
    decimal? MaxDiscount,
    string?  UpdatedAt
);

public sealed record SellerDto(
    [Required] string Id,
    string? MobileId,
    [Required] string Name,
    string? Email,
    string? PasswordHash,   // MOB_SENHA do ERP (PIN text claro — armazenado criptografado na VPS)
    decimal? MaxDiscount,
    decimal? CommissionRate
);

public sealed record CustomerDto(
    [Required] string Id,
    [Required] string Name,
    string? TradeName,
    string? Cnpj,
    string? Phone,
    string? Mobile,
    string? Email,
    string? City,
    string? State,
    decimal? CreditLimit,
    string? Status,
    string? SellerId,
    /// <summary>ID da tabela de preço vinculada ao cliente (CLIENTES.ID_TABELA).</summary>
    string? PriceTableId = null
);

public sealed record PaymentSpeciesDto(
    [Required] string Id,
    [Required] string Name,
    string? Type,
    int Days
);

public sealed record PaymentConditionDto(
    [Required] string Id,
    [Required] string Descricao,
    decimal? DescontoMax,
    int? Parcelas,
    int? DiasEntrada,
    int? DiasParcelas,
    int? MobOrdem
);

public sealed record NaturezaDto(
    [Required] string Id,
    [Required] string Descricao,
    string? DescricaoNota,
    string? CodigoFiscal,
    string? Es,
    int?    MobOrdem
);

public sealed record FinancialDto(
    [Required] string Id,
    string? CustomerId,
    string? DocNumber,
    decimal Amount,
    decimal? Interest,
    string? DueDate,
    string? PaymentSpeciesId,
    bool IsPaid,
    string? Type,
    string? PaymentDate
);

// ─────────────────────────────────────────────────────────────────────────────
// PULL: Flutter ← API  (dados servidos ao app)
// ─────────────────────────────────────────────────────────────────────────────

// Respostas paginadas/datadas para suportar delta sync
public sealed record SyncResponse<T>(
    IReadOnlyList<T> Data,
    int Total,
    string SyncedAt
);

// ─────────────────────────────────────────────────────────────────────────────
// PEDIDOS: Flutter → API → Worker → Firebird
// ─────────────────────────────────────────────────────────────────────────────

public sealed record OrderItemDto(
    [Required] string   ProductCode,
    [Required] string   ProductName,
    [Required] decimal  Quantity,
    [Required] decimal  UnitPrice,
    decimal Discount = 0
);

public sealed record CreateOrderRequest(
    [Required] string             Id,
    [Required] string             CustomerId,
    [Required] string             SellerId,
    [Required] decimal            TotalAmount,
    string?                       Notes,
    string?                       PaymentSpeciesId,
    string?                       PaymentConditionId,
    int?                          PaymentDays,
    [property: JsonConverter(typeof(IntToStringJsonConverter))] string? NaturezaId,
    decimal                       DiscountPercent = 0,
    decimal                       DiscountValue   = 0,
    [Required] List<OrderItemDto> Items           = null!
);

public sealed record SyncOrdersRequest(List<CreateOrderRequest> Orders);

public sealed record SyncOrdersResponse(
    int Accepted,
    int Duplicates,
    List<string> Errors
);

public sealed record OrderStatusDto(
    string  Id,
    string  Status,       // pending | processing | synced | error
    string? ErpOrderId,   // ID gerado pelo Firebird após sync (mudado para string)
    string? ErrorMessage,
    string  CreatedAt,
    string? SyncedAt
);

// ─────────────────────────────────────────────────────────────────────────────
// WORKER: API → Worker  (pedidos pendentes para processar no Firebird)
// ─────────────────────────────────────────────────────────────────────────────

public sealed record PendingOrderDto(
    string             Id,
    string             CustomerId,
    string             SellerId,
    decimal            TotalAmount,
    string?            Notes,
    string?            PaymentSpeciesId,
    string?            PaymentSpeciesName,
    string?            PaymentConditionId,
    string?            PaymentConditionName,
    int?               PaymentDays,
    [property: JsonConverter(typeof(IntToStringJsonConverter))] string? NaturezaId,
    decimal            DiscountPercent,
    decimal            DiscountValue,
    int                PaymentInstallments       = 1,   // FORMA_PGTO.PARCELAS
    int                PaymentDaysPerInstallment = 30,  // FORMA_PGTO.DIAS_PARCELAS
    int                PaymentEntryDays          = 0,   // FORMA_PGTO.DIAS_ENTRADA
    string             CreatedAt  = "",
    Guid?              BranchId   = null,
    List<OrderItemDto>? Items     = null
);

public sealed record PendingOrdersResponse(List<PendingOrderDto> Orders);

// ─────────────────────────────────────────────────────────────────────────────
// RESPOSTAS COMUNS
// ─────────────────────────────────────────────────────────────────────────────

public sealed record SuccessResponse(string Message, int Count = 0);
public sealed record ErrorResponse(string Error, string? Detail = null);

public sealed record ConfirmOrderRequest(string ErpOrderId);
public sealed record ReportErrorRequest(string ErrorMessage);

// ────────────────────────────────────────────────────────────────────────────
// PUSH REQUESTS (Worker → API)
// ────────────────────────────────────────────────────────────────────────────

public sealed record PushSellersRequest(List<SellerDto>? Sellers);
public sealed record PushCatalogRequest(List<ProductDto>? Products);
public sealed record PushCustomersRequest(List<CustomerDto>? Customers);
public sealed record PushPaymentSpeciesRequest(List<PaymentSpeciesDto>? Species);
public sealed record PushPaymentConditionRequest(List<PaymentConditionDto>? Conditions);
public sealed record PushNaturezaRequest(List<NaturezaDto>? Naturezas);
public sealed record PushFinancialsRequest(List<FinancialDto>? Financials);
public sealed record PushPriceTablesRequest(List<PriceTableDto>? Tables);
public sealed record PushProductPricesRequest(List<ProductPriceDto>? Prices);
public sealed record PushSalesRankingsRequest(List<System.Text.Json.JsonElement>? Rankings);

// ─────────────────────────────────────────────────────────────────────────────
// Tabelas de Preço — TABELA_PRECOS / TABELA_PRECOS_ITENS
// ─────────────────────────────────────────────────────────────────────────────

/// <summary>
/// Cabeçalho de uma tabela de preço do ERP.
/// PRECOT_P é o percentual de markup sobre o preço base.
/// </summary>
public sealed record PriceTableDto(
    [Required] string Id,
    [Required] string Name,
    decimal MarkupPct
);

/// <summary>
/// Preço específico de um produto em uma tabela de preço (TABELA_PRECOS_ITENS).
/// Calculado por MOB_TABELAPRECO: PRECO = PRECO_BASE + (PRECO_BASE × PRECOT_P%).
/// </summary>
public sealed record ProductPriceDto(
    [Required] string ProductCode,
    [Required] string PriceTableId,
    decimal Price
);

public class IntToStringJsonConverter : JsonConverter<string>
{
    public override string? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType == JsonTokenType.Number)
        {
            return reader.TryGetInt64(out long l) ? l.ToString() : reader.GetDouble().ToString();
        }
        if (reader.TokenType == JsonTokenType.String)
        {
            return reader.GetString();
        }
        if (reader.TokenType == JsonTokenType.Null)
        {
            return null;
        }
        if (reader.TokenType == JsonTokenType.True) return "true";
        if (reader.TokenType == JsonTokenType.False) return "false";
        
        throw new JsonException($"Unexpected token type {reader.TokenType} when converting to string.");
    }

    public override void Write(Utf8JsonWriter writer, string value, JsonSerializerOptions options)
    {
        writer.WriteStringValue(value);
    }
}

