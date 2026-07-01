from fastapi import APIRouter, Depends, Request, Form, status, HTTPException
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
from datetime import datetime
import secrets
from config.database import get_db, get_identity_db
from config.security import get_current_user_web, get_current_user_api
from modules.companies.models import Company, CompanyModule
from modules.api_keys.models import ApiKey

router = APIRouter()
templates = Jinja2Templates(directory="templates")

@router.get("/api-keys", response_class=HTMLResponse)
def list_api_keys(
    request: Request,
    local_db: Session = Depends(get_db),
    identity_db: Session = Depends(get_identity_db),
    current_user = Depends(get_current_user_web)
):
    # Fetch from local DB
    api_keys = local_db.query(ApiKey).order_by(ApiKey.created_at.desc()).all()
    
    # Map companies centrally in memory
    for key in api_keys:
        key.company = identity_db.query(Company).filter(Company.id == key.company_id).first()
        
    # Only active companies with coliseu-speed centrally
    companies = identity_db.query(Company)\
        .join(CompanyModule, Company.id == CompanyModule.company_id)\
        .filter(CompanyModule.module_slug.in_(["coliseu-speed", "coliseuspeed"]), CompanyModule.is_active == True)\
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
    local_db: Session = Depends(get_db),
    current_user = Depends(get_current_user_web)
):
    api_key = ApiKey(
        company_id=company_id,
        key=f"cs_key_{secrets.token_hex(16)}",
        secret=f"cs_sec_{secrets.token_hex(24)}",
        name=key_name
    )
    local_db.add(api_key)
    local_db.commit()
    return RedirectResponse(url="/adm/api-keys", status_code=status.HTTP_303_SEE_OTHER)

# AJAX endpoint to generate a new key
@router.post("/api/companies/{company_id}/api-keys")
def generate_api_key_api(
    company_id: str,
    local_db: Session = Depends(get_db),
    current_user = Depends(get_current_user_api)
):
    api_key = ApiKey(
        company_id=company_id,
        key=f"cs_key_{secrets.token_hex(16)}",
        secret=f"cs_sec_{secrets.token_hex(24)}",
        name="Chave de Integração"
    )
    local_db.add(api_key)
    local_db.commit()
    local_db.refresh(api_key)
    return api_key

# AJAX endpoint to revoke key
@router.delete("/api/companies/{company_id}/api-keys/{key_id}")
def revoke_api_key_api(
    company_id: str,
    key_id: int,
    local_db: Session = Depends(get_db),
    current_user = Depends(get_current_user_api)
):
    key = local_db.query(ApiKey).filter(
        ApiKey.id == key_id,
        ApiKey.company_id == company_id
    ).first()
    
    if not key:
        return JSONResponse(status_code=404, content={"success": False, "detail": "Chave não encontrada"})
        
    key.is_active = False
    local_db.commit()
    return {"success": True, "message": "Chave revogada com sucesso"}
