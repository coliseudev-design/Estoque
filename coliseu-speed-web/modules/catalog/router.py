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
    
    products = await api_client.get_products()
    return templates.TemplateResponse("catalog/list.html", {
        "request": request,
        "products": products,
        "rep_name": rep_name,
        "selected_branch_name": branch_name,
        "active_page": "catalog"
    })

@router.get("/api/catalog/query")
async def api_catalog_query(
    q: str = Query("", alias="q")
):
    products = await api_client.get_products(q)
    return JSONResponse(content=products)
