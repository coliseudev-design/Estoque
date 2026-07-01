from fastapi import APIRouter, Depends, Request, HTTPException
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from utils.api_client import api_client

router = APIRouter()
templates = Jinja2Templates(directory="templates")

@router.get("/", response_class=HTMLResponse)
async def dashboard_view(request: Request):
    token = request.cookies.get("rep_token")
    if not token:
        raise HTTPException(status_code=307, headers={"Location": "/login"})
        
    rep_name = request.cookies.get("rep_name")
    branch_name = request.cookies.get("rep_branch_name")
    branch_id = request.cookies.get("rep_branch_id")
    seller_id = request.cookies.get("rep_seller_id")
    
    # Query KPIs and sync statuses from middleware
    kpis = await api_client.get_performance_kpis(token=token, seller_id=seller_id, branch_id=branch_id)
    orders = await api_client.get_orders(token=token, seller_id=seller_id, branch_id=branch_id)
    sync_status = await api_client.get_sync_status()

    return templates.TemplateResponse("dashboard/index.html", {
        "request": request,
        "kpis": kpis,
        "recent_orders": orders[:5],
        "sync_status": sync_status,
        "rep_name": rep_name,
        "selected_branch_name": branch_name,
        "active_page": "dashboard"
    })
