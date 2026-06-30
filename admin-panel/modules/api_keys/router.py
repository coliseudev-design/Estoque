from fastapi import APIRouter, Depends, Request, Form, status, HTTPException
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
from datetime import datetime
import secrets
from config.database import get_db
from config.security import get_current_user_web, get_current_user_api
from modules.companies.models import Company, CompanyModule
from modules.api_keys.models import ApiKey

router = APIRouter()
templates = Jinja2Templates(directory="templates")

@router.get("/api-keys", response_class=HTMLResponse)
def list_api_keys(
    request: Request,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user_web)
):
    api_keys = db.query(ApiKey).join(Company).order_by(ApiKey.created_at.desc()).all()
    
    # Only active companies with coliseu-speed
    companies = db.query(Company)\
        .join(CompanyModule, Company.id == CompanyModule.company_id)\
        .filter(CompanyModule.module_slug == "coliseu-speed", CompanyModule.is_active == True)\
        .all()

    return templates.TemplateResponse("api_keys/list.html", {
        "request": request,
        "api_keys": api_keys,
        "companies": companies,
        "current_user": current_user,
        "active_page": "api_keys"
    })

# Quick form generation redirect
@router.post("/api-keys/generate")
def generate_api_key_redirect(
    company_id: str = Form(...),
    key_name: str = Form(...),
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user_web)
):
    api_key = ApiKey(
        company_id=company_id,
        key=f"cs_key_{secrets.token_hex(16)}",
        secret=f"cs_sec_{secrets.token_hex(24)}",
        name=key_name
    )
    db.add(api_key)
    db.commit()
    return RedirectResponse(url="/adm/api-keys", status_code=status.HTTP_303_SEE_OTHER)

# AJAX endpoint to generate a new key
@router.post("/api/companies/{company_id}/api-keys")
def generate_api_key_api(
    company_id: str,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user_api)
):
    api_key = ApiKey(
        company_id=company_id,
        key=f"cs_key_{secrets.token_hex(16)}",
        secret=f"cs_sec_{secrets.token_hex(24)}",
        name="Chave de Integração"
    )
    db.add(api_key)
    db.commit()
    db.refresh(api_key)
    return api_key

# AJAX endpoint to revoke key
@router.delete("/api/companies/{company_id}/api-keys/{key_id}")
def revoke_api_key_api(
    company_id: str,
    key_id: int,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user_api)
):
    key = db.query(ApiKey).filter(
        ApiKey.id == key_id,
        ApiKey.company_id == company_id
    ).first()
    
    if not key:
        return JSONResponse(status_code=404, content={"success": False, "detail": "Chave não encontrada"})
        
    key.is_active = False
    db.commit()
    return {"success": True, "message": "Chave revogada com sucesso"}
