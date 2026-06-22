using ColiseuSales.Api.Auth;
using ColiseuSales.Api.Data;
using ColiseuSales.Api.Data.Entities;
using ColiseuSales.Shared.Dtos;
using Microsoft.EntityFrameworkCore;

namespace ColiseuSales.Api.Endpoints;

/// <summary>
/// Endpoints de pedidos.
///
/// Fluxo completo:
/// Flutter → POST /api/sync/orders   → salva na VPS (status: pending)
/// Worker  → GET  /api/orders/pending → busca pendentes
/// Worker  → POST /api/orders/{id}/confirm  → marca como synced + id ERP
/// Worker  → POST /api/orders/{id}/error    → marca como error
/// Flutter → GET  /api/orders/{id}   → consulta status do pedido
/// </summary>
public static class OrderEndpoints
{
    public static void MapOrderEndpoints(this WebApplication app)
    {
        var orders = app.MapGroup("/api")
            .WithTags("Orders")
            .RequireAuthorization();

        // Flutter envia pedido
        orders.MapPost("/sync/orders", CreateOrder)
            .WithName("CreateOrder")
            .WithSummary("Flutter → API: registra pedido para processar no Firebird");

        // Worker busca pedidos pendentes
        orders.MapGet("/orders/pending", GetPendingOrders)
            .WithName("GetPendingOrders")
            .WithSummary("Worker ← API: lista pedidos aguardando inserção no Firebird");

        // Worker confirma pedido inserido no ERP
        orders.MapPost("/orders/{id}/confirm", ConfirmOrder)
            .WithName("ConfirmOrder")
            .WithSummary("Worker → API: confirma que pedido foi inserido no Firebird");

        // Worker reporta erro
        orders.MapPost("/orders/{id}/error", ReportOrderError)
            .WithName("ReportOrderError")
            .WithSummary("Worker → API: registra erro ao processar pedido");

        // Flutter consulta status
        orders.MapGet("/orders/{id}", GetOrderStatus)
            .WithName("GetOrderStatus")
            .WithSummary("Flutter ← API: consulta status de um pedido específico");
    }

    // ─────────────────────────────────────────────────────────────────────────
    // POST /api/sync/orders — Flutter envia pedido
    // ─────────────────────────────────────────────────────────────────────────

    private static async Task<IResult> CreateOrder(
        SyncOrdersRequest req, AppDbContext db, HttpContext httpContext,
        ILogger<Program> logger, CancellationToken ct)
    {
        var companyId = httpContext.RequireCompanyId();
        if (req.Orders is not { Count: > 0 })
            return Results.BadRequest(new ErrorResponse("Lista de pedidos vazia."));

        int accepted = 0;
        int duplicates = 0;
        var errors = new List<string>();

        foreach (var orderReq in req.Orders)
        {
            try 
            {
                if (string.IsNullOrWhiteSpace(orderReq.Id))
                {
                    errors.Add("ID do pedido ausente.");
                    continue;
                }

                // Idempotência
                var existing = await db.Orders.AnyAsync(o => o.Id == orderReq.Id, ct);
                if (existing)
                {
                    duplicates++;
                    continue;
                }

                var now = DateTime.UtcNow.ToString("O");
                var order = new Order
                {
                    Id               = orderReq.Id,
                    CompanyId        = companyId,
                    CustomerId       = orderReq.CustomerId,
                    SellerId         = orderReq.SellerId,
                    TotalAmount      = orderReq.TotalAmount,
                    Notes            = orderReq.Notes,
                    PaymentSpeciesId = orderReq.PaymentSpeciesId,
                    PaymentConditionId = orderReq.PaymentConditionId,
                    PaymentDays      = orderReq.PaymentDays,
                    NaturezaId       = orderReq.NaturezaId,
                    DiscountPercent  = orderReq.DiscountPercent,
                    DiscountValue    = orderReq.DiscountValue,
                    Status           = "pending",
                    CreatedAt        = now,
                    Items            = orderReq.Items.Select(i => new OrderItem
                    {
                        ProductCode  = i.ProductCode,
                        ProductName  = i.ProductName,
                        Quantity     = i.Quantity,
                        UnitPrice    = i.UnitPrice,
                        Discount     = i.Discount,
                    }).ToList(),
                };

                db.Orders.Add(order);
                accepted++;
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "[Orders] Erro ao processar pedido {Id}", orderReq.Id);
                errors.Add($"Pedido {orderReq.Id}: {ex.Message}");
            }
        }

        if (accepted > 0)
        {
            await db.SaveChangesAsync(ct);
            logger.LogInformation("[Orders] Batch processado: {Accepted} aceitos, {Duplicates} duplicados, {Errors} erros.", 
                accepted, duplicates, errors.Count);
        }

        return Results.Ok(new SyncOrdersResponse(accepted, duplicates, errors));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GET /api/orders/pending — Worker busca pedidos a processar
    // ─────────────────────────────────────────────────────────────────────────

    private static async Task<IResult> GetPendingOrders(
        AppDbContext db, HttpContext httpContext, CancellationToken ct)
    {
        var companyId = httpContext.RequireCompanyId();
        var orders = await db.Orders
            .Where(o => o.Status == "pending" && o.CompanyId == companyId)
            .Include(o => o.Items)
            .OrderBy(o => o.CreatedAt)
            .Take(50)   // processa em lotes de 50
            .ToListAsync(ct);

        // Marca como "processing" para evitar que outro ciclo de Worker os busque
        foreach (var o in orders)
            o.Status = "processing";

        if (orders.Count > 0)
            await db.SaveChangesAsync(ct);

        var dtos = orders.Select(o => new PendingOrderDto(
            o.Id, o.CustomerId, o.SellerId, o.TotalAmount, o.Notes,
            o.PaymentSpeciesId, null, o.PaymentConditionId, null, o.PaymentDays, o.NaturezaId,
            o.DiscountPercent, o.DiscountValue,
            1, 30, 0,
            o.CreatedAt,
            null,
            o.Items.Select(i => new OrderItemDto(
                i.ProductCode, i.ProductName, i.Quantity, i.UnitPrice, i.Discount))
            .ToList()
        )).ToList();

        return Results.Ok(new PendingOrdersResponse(dtos));
    }

    // ─────────────────────────────────────────────────────────────────────────
    // POST /api/orders/{id}/confirm — Worker confirma inserção no Firebird
    // ─────────────────────────────────────────────────────────────────────────

    private static async Task<IResult> ConfirmOrder(
        string id, ConfirmOrderRequest req, AppDbContext db,
        ILogger<Program> logger, CancellationToken ct)
    {
        var order = await db.Orders.FindAsync([id], ct);
        if (order is null) return Results.NotFound(new ErrorResponse($"Pedido {id} não encontrado."));

        order.Status     = "synced";
        order.ErpOrderId = req.ErpOrderId;
        order.SyncedAt   = DateTime.UtcNow.ToString("O");

        await db.SaveChangesAsync(ct);

        logger.LogInformation("[Orders] Pedido {Id} confirmado — ERP ID={ErpId}.", id, req.ErpOrderId);
        return Results.Ok(new { message = "Confirmado.", erpOrderId = req.ErpOrderId });
    }

    // ─────────────────────────────────────────────────────────────────────────
    // POST /api/orders/{id}/error — Worker registra falha
    // ─────────────────────────────────────────────────────────────────────────

    private static async Task<IResult> ReportOrderError(
        string id, ReportErrorRequest req, AppDbContext db,
        ILogger<Program> logger, CancellationToken ct)
    {
        var order = await db.Orders.FindAsync([id], ct);
        if (order is null) return Results.NotFound(new ErrorResponse($"Pedido {id} não encontrado."));

        order.Status       = "error";
        order.ErrorMessage = req.ErrorMessage;

        await db.SaveChangesAsync(ct);

        logger.LogWarning("[Orders] Pedido {Id} com erro: {Error}", id, req.ErrorMessage);
        return Results.Ok(new { message = "Erro registrado." });
    }

    // ─────────────────────────────────────────────────────────────────────────
    // GET /api/orders/{id} — Flutter consulta status
    // ─────────────────────────────────────────────────────────────────────────

    private static async Task<IResult> GetOrderStatus(
        string id, AppDbContext db, CancellationToken ct)
    {
        var order = await db.Orders.FindAsync([id], ct);
        if (order is null) return Results.NotFound(new ErrorResponse($"Pedido {id} não encontrado."));

        return Results.Ok(new OrderStatusDto(
            order.Id, order.Status, order.ErpOrderId,
            order.ErrorMessage, order.CreatedAt, order.SyncedAt));
    }
}
