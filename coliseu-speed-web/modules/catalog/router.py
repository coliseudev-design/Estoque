from fastapi import APIRouter, Depends, Request, HTTPException, Query
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from utils.api_client import api_client

router = APIRouter()
templates = Jinja2Templates(directory="templates")

@router.get("/catalog", response_class=HTMLResponse)
async def catalog_view(request: Request):
    token = request.cookies.get("rep_token")
    if not token:
        raise HTTPException(status_code=307, headers={"Location": "/login"})
        
    rep_name = request.cookies.get("rep_name")
    branch_name = request.cookies.get("rep_branch_name")
    branch_id = request.cookies.get("rep_branch_id")
    api_key = request.cookies.get("rep_api_key")
    
    products = await api_client.get_products(token=token, branch_id=branch_id, api_key=api_key)
    orders = await api_client.get_orders(token=token, seller_id=request.cookies.get("rep_seller_id"), branch_id=branch_id, api_key=api_key)
    return templates.TemplateResponse("catalog/list.html", {
        "request": request,
        "products": products,
        "orders": orders,
        "rep_name": rep_name,
        "selected_branch_name": branch_name,
        "active_page": "catalog"
    })

@router.get("/web-api/catalog/query")
async def api_catalog_query(
    request: Request,
    q: str = Query("", alias="q")
):
    token = request.cookies.get("rep_token")
    branch_id = request.cookies.get("rep_branch_id")
    api_key = request.cookies.get("rep_api_key")
    products = await api_client.get_products(token=token, query=q, branch_id=branch_id, api_key=api_key)
    return JSONResponse(content=products)
