from fastapi import APIRouter, Depends, Request, HTTPException, status
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse, PlainTextResponse
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel
from typing import List
import urllib.parse

from utils.api_client import api_client
from utils.admin_client import admin_client
from utils.pdf_generator import generate_order_invoice_text

router = APIRouter()
templates = Jinja2Templates(directory="templates")

# Schemas
class OrderItemSchema(BaseModel):
    product_id: str
    quantity: int
    price: float

class OrderCreateSchema(BaseModel):
    customer_id: str
    status: str # 'order' or 'budget'
    payment_condition: str
    items: List[OrderItemSchema]

@router.get("/orders", response_class=HTMLResponse)
async def list_orders(request: Request):
    token = request.cookies.get("rep_token")
    if not token:
        raise HTTPException(status_code=307, headers={"Location": "/login"})
        
    rep_name = request.cookies.get("rep_name")
    branch_name = request.cookies.get("rep_branch_name")
    branch_id = request.cookies.get("rep_branch_id")
    seller_id = request.cookies.get("rep_seller_id")
    
    orders = await api_client.get_orders(token=token, seller_id=seller_id, branch_id=branch_id)
    return templates.TemplateResponse("orders/list.html", {
        "request": request,
        "orders": orders,
        "rep_name": rep_name,
        "selected_branch_name": branch_name,
        "active_page": "orders"
    })

@router.get("/orders/new", response_class=HTMLResponse)
async def new_order_view(request: Request):
    token = request.cookies.get("rep_token")
    if not token:
        raise HTTPException(status_code=307, headers={"Location": "/login"})
        
    rep_name = request.cookies.get("rep_name")
    branch_name = request.cookies.get("rep_branch_name")
    branch_id = request.cookies.get("rep_branch_id")
    seller_id = request.cookies.get("rep_seller_id")
    
    products = await api_client.get_products(token=token, branch_id=branch_id)
    customers = await api_client.get_customers(token=token, seller_id=seller_id, branch_id=branch_id)
    
    return templates.TemplateResponse("orders/new.html", {
        "request": request,
        "products": products,
        "customers": customers,
        "rep_name": rep_name,
        "selected_branch_name": branch_name,
        "active_page": "new_order"
    })

@router.post("/api/orders/new")
async def api_create_order(request: Request, payload: OrderCreateSchema):
    token = request.cookies.get("rep_token")
    seller_id = request.cookies.get("rep_seller_id")
    seller_name = request.cookies.get("rep_name")
    branch_id = request.cookies.get("rep_branch_id")
    
    # Call middleware API to insert order
    res = await api_client.create_order(
        token=token,
        customer_id=payload.customer_id,
        status=payload.status,
        payment_condition=payload.payment_condition,
        items=[item.dict() for item in payload.items],
        seller_id=seller_id,
        seller_name=seller_name,
        branch_id=branch_id
    )
    if not res.get("success", False):
        raise HTTPException(status_code=400, detail=res.get("detail", "Erro desconhecido faturamento."))
    return res

@router.get("/orders/{id}", response_class=HTMLResponse)
async def view_order(id: str, request: Request):
    token = request.cookies.get("rep_token")
    if not token:
        raise HTTPException(status_code=307, headers={"Location": "/login"})
        
    rep_name = request.cookies.get("rep_name")
    branch_name = request.cookies.get("rep_branch_name")
    branch_id = request.cookies.get("rep_branch_id")
    seller_id = request.cookies.get("rep_seller_id")
    
    # Query order from middleware database
    orders = await api_client.get_orders(token=token, seller_id=seller_id, branch_id=branch_id)
    order = next((o for o in orders if str(o["id"]) == id), None)
    if not order:
        raise HTTPException(status_code=404, detail="Pedido não encontrado")
        
    # Query active integrations flags from SaaS Admin Panel
    integrations = await admin_client.get_active_integrations()
    
    invoice_text = generate_order_invoice_text(order)

    return templates.TemplateResponse("orders/detail.html", {
        "request": request,
        "order": order,
        "integrations": integrations,
        "invoice_text": invoice_text,
        "rep_name": rep_name,
        "selected_branch_name": branch_name,
        "active_page": "orders"
    })

# Baixar PDF (servido como texto puro imitando um arquivo de PDF/Nota para teste)
@router.get("/orders/{id}/pdf")
async def download_order_pdf(id: str, request: Request):
    token = request.cookies.get("rep_token")
    branch_id = request.cookies.get("rep_branch_id")
    seller_id = request.cookies.get("rep_seller_id")
    
    orders = await api_client.get_orders(token=token, seller_id=seller_id, branch_id=branch_id)
    order = next((o for o in orders if str(o["id"]) == id), None)
    if not order:
        raise HTTPException(status_code=404, detail="Pedido não encontrado")
    invoice_text = generate_order_invoice_text(order)
    return PlainTextResponse(content=invoice_text, headers={"Content-Disposition": f"attachment; filename=pedido_{id}.txt"})

# WhatsApp trigger link generator
@router.get("/orders/{id}/share/whatsapp")
async def share_whatsapp(id: str, request: Request):
    token = request.cookies.get("rep_token")
    branch_id = request.cookies.get("rep_branch_id")
    seller_id = request.cookies.get("rep_seller_id")
    
    orders = await api_client.get_orders(token=token, seller_id=seller_id, branch_id=branch_id)
    order = next((o for o in orders if str(o["id"]) == id), None)
    if not order:
        raise HTTPException(status_code=404, detail="Pedido não encontrado")
        
    message = f"Olá, segue o resumo do seu pedido *#{id}* no valor total de R$ {order['total_amount']:.2f}. Acesse o link para conferir."
    url_encoded = urllib.parse.quote(message)
    
    # Check WhatsApp API configs in Admin Panel
    integrations = await admin_client.get_active_integrations()
    phone = integrations.get("whatsapp", {}).get("configuration", {}).get("phone", "")
    
    return RedirectResponse(url=f"https://api.whatsapp.com/send?phone={phone}&text={url_encoded}")

# Email mock trigger
@router.post("/orders/{id}/share/email")
async def share_email(id: str):
    # Simulate sending SMTP
    return {"success": True, "message": "Email disparado via servidor SMTP cadastrado no Admin."}

# Contract template mock generator
@router.get("/orders/{id}/share/contract")
async def share_contract(id: str, request: Request):
    token = request.cookies.get("rep_token")
    branch_id = request.cookies.get("rep_branch_id")
    seller_id = request.cookies.get("rep_seller_id")
    
    orders = await api_client.get_orders(token=token, seller_id=seller_id, branch_id=branch_id)
    order = next((o for o in orders if str(o["id"]) == id), None)
    if not order:
        raise HTTPException(status_code=404, detail="Pedido não encontrado")
        
    contract_text = f"""
==================================================
        CONTRATO DE COMPRA E VENDA COMERCIAL
==================================================
Pelo presente instrumento, a empresa ColiseuSpeed Ltda
vende à contratante {order['customer_name']}
os itens especificados na fatura do Pedido #{id}
pelo montante global de R$ {order['total_amount']:.2f}.
--------------------------------------------------
Assinado digitalmente por ambas as partes.
==================================================
"""
    return PlainTextResponse(content=contract_text.strip())

# Fiscal NF-e transmit simulation
@router.get("/orders/{id}/share/fiscal")
async def share_fiscal(id: str, request: Request):
    token = request.cookies.get("rep_token")
    branch_id = request.cookies.get("rep_branch_id")
    seller_id = request.cookies.get("rep_seller_id")
    
    orders = await api_client.get_orders(token=token, seller_id=seller_id, branch_id=branch_id)
    order = next((o for o in orders if str(o["id"]) == id), None)
    if not order:
        raise HTTPException(status_code=404, detail="Pedido não encontrado")
        
    fiscal_response = f"""
==================================================
    NF-e TRANSMITIDA COM SUCESSO - SEFAZ SP
==================================================
Chave de Acesso NF-e: 352606607011900001045500100000{id[:10]}1234567890
Protocolo de Autorização: 135260000{id[:10]}99824
Data/Hora Processamento: 2026-06-30T15:50:00Z
Status: 100 - Autorizado o uso da NF-e
==================================================
"""
    return PlainTextResponse(content=fiscal_response.strip())
