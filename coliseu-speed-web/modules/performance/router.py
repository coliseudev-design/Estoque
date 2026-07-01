from fastapi import APIRouter, Depends, Request, HTTPException
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from utils.api_client import api_client

router = APIRouter()
templates = Jinja2Templates(directory="templates")

@router.get("/performance", response_class=HTMLResponse)
async def performance_view(request: Request):
    token = request.cookies.get("rep_token")
    if not token:
        raise HTTPException(status_code=307, headers={"Location": "/login"})
        
    rep_name = request.cookies.get("rep_name")
    branch_name = request.cookies.get("rep_branch_name")
    branch_id = request.cookies.get("rep_branch_id")
    seller_id = request.cookies.get("rep_seller_id")
    api_key = request.cookies.get("rep_api_key")
    
    kpis = await api_client.get_performance_kpis(token=token, seller_id=seller_id, branch_id=branch_id, api_key=api_key)
    products = await api_client.get_products(token=token, branch_id=branch_id, api_key=api_key)
    orders = await api_client.get_orders(token=token, seller_id=seller_id, branch_id=branch_id, api_key=api_key)
    return templates.TemplateResponse("performance/index.html", {
        "request": request,
        "kpis": kpis,
        "products": products,
        "orders": orders,
        "rep_name": rep_name,
        "selected_branch_name": branch_name,
        "active_page": "performance"
    })
