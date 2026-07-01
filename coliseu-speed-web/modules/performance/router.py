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
    
    kpis = await api_client.get_performance_kpis(token=token, seller_id=seller_id, branch_id=branch_id)
    return templates.TemplateResponse("performance/index.html", {
        "request": request,
        "kpis": kpis,
        "rep_name": rep_name,
        "selected_branch_name": branch_name,
        "active_page": "performance"
    })
