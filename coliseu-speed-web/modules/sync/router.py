from fastapi import APIRouter, Depends, Request, HTTPException
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from utils.api_client import api_client

router = APIRouter()
templates = Jinja2Templates(directory="templates")

@router.get("/sync", response_class=HTMLResponse)
async def sync_view(request: Request):
    token = request.cookies.get("rep_token")
    if not token:
        raise HTTPException(status_code=307, headers={"Location": "/login"})
        
    rep_name = request.cookies.get("rep_name")
    branch_name = request.cookies.get("rep_branch_name")
    
    sync = await api_client.get_sync_status()
    return templates.TemplateResponse("sync/index.html", {
        "request": request,
        "sync": sync,
        "rep_name": rep_name,
        "selected_branch_name": branch_name,
        "active_page": "sync"
    })

@router.post("/api/sync/run")
async def api_sync_run():
    # Simulate force ERP catalog updates
    return JSONResponse(content={"success": True, "message": "Catálogo do Firebird sincronizado com sucesso."})
