from fastapi import APIRouter, Depends, Request, Form, status, HTTPException
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
from datetime import datetime
from config.database import get_db
from config.security import get_current_user_web, get_current_user_api
from utils.license_validator import validate_license_on_sales
from modules.companies.models import Company
from modules.licenses.models import License

router = APIRouter()
templates = Jinja2Templates(directory="templates")

@router.get("/licenses", response_class=HTMLResponse)
def list_licenses(
    request: Request,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user_web)
):
    licenses = db.query(License).join(Company).order_by(License.created_at.desc()).all()
    return templates.TemplateResponse("licenses/list.html", {
        "request": request,
        "licenses": licenses,
        "current_user": current_user,
        "active_page": "licenses"
    })

@router.get("/licenses/new", response_class=HTMLResponse)
def new_license_form(
    request: Request,
    company_id: int = None,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user_web)
):
    companies = db.query(Company).filter(Company.status == "active").all()
    return templates.TemplateResponse("licenses/form.html", {
        "request": request,
        "companies": companies,
        "selected_company_id": company_id,
        "current_user": current_user,
        "active_page": "licenses"
    })

@router.post("/licenses/new")
async def create_license(
    request: Request,
    company_id: int = Form(...),
    license_key: str = Form(...),
    product_type: str = Form("coliseu_speed"),
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user_web)
):
    companies = db.query(Company).filter(Company.status == "active").all()
    
    # Check if this license key is already activated
    existing = db.query(License).filter(License.license_key == license_key).first()
    if existing:
        return templates.TemplateResponse("licenses/form.html", {
            "request": request,
            "companies": companies,
            "selected_company_id": company_id,
            "current_user": current_user,
            "active_page": "licenses",
            "flash_message": "Esta chave de licença já foi ativada em outro tenant.",
            "flash_type": "error"
        })

    # Validate against central service
    validation = await validate_license_on_sales(license_key)
    if not validation.get("valid", False):
        return templates.TemplateResponse("licenses/form.html", {
            "request": request,
            "companies": companies,
            "selected_company_id": company_id,
            "current_user": current_user,
            "active_page": "licenses",
            "flash_message": f"Chave de licença inválida: {validation.get('error', 'Chave rejeitada pelo servidor central.')}",
            "flash_type": "error"
        })

    # Create license
    exp_date_str = validation.get("expiration_date")
    expiration_date = None
    if exp_date_str:
        # standard ISO format parsing
        try:
            expiration_date = datetime.fromisoformat(exp_date_str.replace("Z", "+00:00"))
        except:
            expiration_date = datetime.utcnow() # fallback

    new_lic = License(
        company_id=company_id,
        license_key=license_key,
        product_type=validation.get("product_type", product_type),
        status="active",
        activation_date=datetime.utcnow(),
        expiration_date=expiration_date,
        max_users=validation.get("max_users", 5),
        max_branches=validation.get("max_branches", 1),
        features=validation.get("features", [])
    )
    db.add(new_lic)
    db.commit()

    return RedirectResponse(
        url=f"/adm/companies/{company_id}",
        status_code=status.HTTP_303_SEE_OTHER
    )

@router.get("/api/companies/{id}/licenses/{license_id}/validate")
def api_validate_license(
    id: int,
    license_id: int,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user_api)
):
    license = db.query(License).filter(License.id == license_id, License.company_id == id).first()
    if not license:
        return JSONResponse(status_code=404, content={"valid": False, "detail": "Licença não encontrada"})
        
    # Check expiration date
    is_valid = license.status == "active"
    if license.expiration_date and license.expiration_date < datetime.utcnow():
        is_valid = False
        license.status = "expired"
        db.commit()

    return {
        "valid": is_valid,
        "license_key": license.license_key,
        "product_type": license.product_type,
        "status": license.status,
        "expiration_date": license.expiration_date
    }
