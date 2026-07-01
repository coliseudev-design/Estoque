from fastapi import APIRouter, Depends, Request, status, HTTPException
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
from datetime import datetime
from config.database import get_db, get_identity_db
from config.security import get_current_user_web, get_current_user_api
from modules.companies.models import Company
from modules.instances.models import Instance

router = APIRouter()
templates = Jinja2Templates(directory="templates")

@router.get("/instances", response_class=HTMLResponse)
def list_instances(
    request: Request,
    local_db: Session = Depends(get_db),
    identity_db: Session = Depends(get_identity_db),
    current_user = Depends(get_current_user_web)
):
    # Fetch from local DB
    instances = local_db.query(Instance).order_by(Instance.created_at.desc()).all()
    
    # Map companies centrally in memory
    for instance in instances:
        instance.company = identity_db.query(Company).filter(Company.id == instance.company_id).first()
        
    return templates.TemplateResponse("instances/list.html", {
        "request": request,
        "instances": instances,
        "current_user": current_user,
        "active_page": "instances"
    })

@router.post("/api/companies/{company_id}/instances/{instance_id}/sync")
def force_instance_sync(
    company_id: str,
    instance_id: int,
    local_db: Session = Depends(get_db),
    current_user = Depends(get_current_user_api)
):
    instance = local_db.query(Instance).filter(
        Instance.id == instance_id,
        Instance.company_id == company_id
    ).first()
    
    if not instance:
        return JSONResponse(status_code=404, content={"success": False, "message": "Instância não encontrada"})

    # Update sync timestamp and make online
    instance.last_sync = datetime.utcnow()
    instance.status = "online"
    local_db.commit()

    return {"success": True, "message": "Sincronização forçada realizada com sucesso", "last_sync": instance.last_sync}
