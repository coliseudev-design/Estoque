using System.ComponentModel.DataAnnotations;

namespace ColiseuSales.Api.Data.Entities;

// ─────────────────────────────────────────────────────────────────────────────
// Entidades do banco SQLite local da VPS (buffer entre Worker e Flutter)
// Rule-03: CompanyId obrigatório em todas as entidades para isolamento multi-tenant.
// ─────────────────────────────────────────────────────────────────────────────

public sealed class Product
{
    /// <summary>Chave composta configurada no OnModelCreating (Code + CompanyId).</summary>
    public string  Code              { get; set; } = null!;
    public string  CompanyId         { get; set; } = null!;
    public string  Name              { get; set; } = null!;
    public string? NameShort         { get; set; }
    public decimal? Price            { get; set; }
    public decimal? PriceMin         { get; set; }
    public decimal? PriceCost        { get; set; }
    public decimal Stock             { get; set; }
    public string? Unit              { get; set; }
    public string? Brand             { get; set; }
    public string? BarCode           { get; set; }
    public string? Reference         { get; set; }
    public decimal? MaxDiscount      { get; set; }
    public string  UpdatedAt         { get; set; } = null!;
    public string  SyncedAt          { get; set; } = null!;
}

public sealed class Seller
{
    [Key] public string  Id           { get; set; } = null!;
    public string  CompanyId          { get; set; } = null!;
    public string? MobileId           { get; set; }
    public string  Name               { get; set; } = null!;
    public string? Email              { get; set; }
    public string? PasswordHash       { get; set; }  // MOB_SENHA — armazenado criptografado
    public decimal? MaxDiscount       { get; set; }
    public decimal? CommissionRate    { get; set; }
    public string  SyncedAt           { get; set; } = null!;
}

public sealed class Customer
{
    [Key] public string  Id           { get; set; } = null!;
    public string  CompanyId          { get; set; } = null!;
    public string  Name               { get; set; } = null!;
    public string? TradeName          { get; set; }
    public string? Cnpj               { get; set; }
    public string? Phone              { get; set; }
    public string? Mobile             { get; set; }
    public string? Email              { get; set; }
    public string? City               { get; set; }
    public string? State              { get; set; }
    public decimal? CreditLimit       { get; set; }
    public string? Status             { get; set; }
    public string? SellerId           { get; set; }
    public string  SyncedAt           { get; set; } = null!;
}

public sealed class PaymentSpecies
{
    [Key] public string  Id           { get; set; } = null!;
    public string  CompanyId          { get; set; } = null!;
    public string  Name               { get; set; } = null!;
    public string? Type               { get; set; }
    public int     Days               { get; set; }
    public string  SyncedAt           { get; set; } = null!;
}

public sealed class PaymentCondition
{
    [Key] public string  Id           { get; set; } = null!;
    public string  CompanyId          { get; set; } = null!;
    public string  Descricao          { get; set; } = null!;
    public decimal? DescontoMax       { get; set; }
    public int?    Parcelas           { get; set; }
    public int?    DiasEntrada        { get; set; }
    public int?    DiasParcelas       { get; set; }
    public int?    MobOrdem           { get; set; }
    public string  SyncedAt           { get; set; } = null!;
}

public sealed class NaturezaOperacao
{
    [Key] public string  Id           { get; set; } = null!;
    public string  CompanyId          { get; set; } = null!;
    public string  Descricao          { get; set; } = null!;
    public string? DescricaoNota      { get; set; }
    public string? CodigoFiscal       { get; set; }
    public string? Es                 { get; set; }
    public int?    MobOrdem           { get; set; }
    public string  SyncedAt           { get; set; } = null!;
}

public sealed class Financial
{
    [Key] public string  Id           { get; set; } = null!;
    public string  CompanyId          { get; set; } = null!;
    public string? CustomerId         { get; set; }
    public string? DocNumber          { get; set; }
    public decimal Amount             { get; set; }
    public decimal? Interest          { get; set; }
    public string? DueDate            { get; set; }
    public string? PaymentSpeciesId   { get; set; }
    public bool    IsPaid             { get; set; }
    public string? Type               { get; set; }
    public string? PaymentDate        { get; set; }
    public string  SyncedAt           { get; set; } = null!;
}

public sealed class Order
{
    [Key] public string  Id                 { get; set; } = null!;
    public string  CompanyId          { get; set; } = null!;
    public string  CustomerId         { get; set; } = null!;
    public string  SellerId           { get; set; } = null!;
    public decimal TotalAmount        { get; set; }
    public string? Notes              { get; set; }
    public string? PaymentSpeciesId   { get; set; }
    public string? PaymentConditionId { get; set; }
    public int?    PaymentDays        { get; set; }
    public string? NaturezaId         { get; set; }
    public decimal DiscountPercent    { get; set; }
    public decimal DiscountValue      { get; set; }
    /// <summary>pending | processing | synced | error</summary>
    public string  Status             { get; set; } = "pending";
    public string? ErpOrderId         { get; set; }
    public string? ErrorMessage       { get; set; }
    public string  CreatedAt          { get; set; } = null!;
    public string? SyncedAt           { get; set; }

    public List<OrderItem> Items      { get; set; } = new();
}

public sealed class OrderItem
{
    [Key] public int     Id           { get; set; }
    public string  OrderId            { get; set; } = null!;
    public string  ProductCode        { get; set; } = null!;
    public string  ProductName        { get; set; } = null!;
    public decimal Quantity           { get; set; }
    public decimal UnitPrice          { get; set; }
    public decimal Discount           { get; set; }

    public Order   Order              { get; set; } = null!;
}

public sealed class SalesRanking
{
    [Key] public string Id { get; set; } = null!;
    public string CompanyId { get; set; } = null!;
    public string SellerId { get; set; } = null!;
    public string Content { get; set; } = null!;
    public string SyncedAt { get; set; } = null!;
}
