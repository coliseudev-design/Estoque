from fastapi import APIRouter, Depends, Request, HTTPException
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from config.config import settings

router = APIRouter()
templates = Jinja2Templates(directory="templates")

@router.get("/settings", response_class=HTMLResponse)
async def settings_view(request: Request):
    token = request.cookies.get("rep_token")
    if not token:
        raise HTTPException(status_code=307, headers={"Location": "/login"})
        
    rep_name = request.cookies.get("rep_name")
    branch_name = request.cookies.get("rep_branch_name")
    
    return templates.TemplateResponse("settings/index.html", {
        "request": request,
        "settings": settings,
        "rep_name": rep_name,
        "selected_branch_name": branch_name,
        "active_page": "settings"
    })
