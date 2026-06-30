from fastapi import APIRouter, Depends, Request, Form, status, HTTPException
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
from datetime import datetime
import uuid
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
    # Retrieve devices joined with companies
    licenses = db.query(License).join(Company).order_by(License.activation_date.desc()).all()
    return templates.TemplateResponse("licenses/list.html", {
        "request": request,
        "licenses": licenses,
        "current_user": current_user,
        "active_page": "licenses"
    })

@router.get("/licenses/new", response_class=HTMLResponse)
def new_license_form(
    request: Request,
    company_id: str = None,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user_web)
):
    companies = db.query(Company).filter(Company.status == 1).all() # 1=Active
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
    company_id: str = Form(...),
    license_key: str = Form(...),
    product_type: str = Form("coliseu_speed"),
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user_web)
):
    companies = db.query(Company).filter(Company.status == 1).all()
    
    # Check if this activation key is already listed
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

    # Validate against central licensing service
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

    # Insert a new device/license record linked to the company
    new_lic = License(
        id=str(uuid.uuid4()),
        company_id=company_id,
        license_key=license_key,
        status=1, # 1 = Active
        activation_date=datetime.utcnow(),
        last_access=datetime.utcnow(),
        model="Dispositivo Faturamento",
        os="Web/Mobile"
    )
    db.add(new_lic)
    db.commit()

    return RedirectResponse(
        url=f"/adm/companies/{company_id}",
        status_code=status.HTTP_303_SEE_OTHER
    )

@router.get("/api/companies/{id}/licenses/{license_id}/validate")
def api_validate_license(
    id: str,
    license_id: str,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user_api)
):
    # Fetch license from central devices table
    license = db.query(License).filter(License.id == license_id, License.company_id == id).first()
    if not license:
        return JSONResponse(status_code=404, content={"valid": False, "detail": "Licença não encontrada"})
        
    is_valid = license.status_code == 1 # 1 = Active in legacy enum

    return {
        "valid": is_valid,
        "license_key": license.license_key,
        "product_type": "coliseu_speed",
        "status": "active" if is_valid else "inactive",
        "expiration_date": None
    }
