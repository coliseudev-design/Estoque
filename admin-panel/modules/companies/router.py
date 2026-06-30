from fastapi import APIRouter, Depends, Request, Form, status, HTTPException
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
import secrets
from config.database import get_db
from config.security import get_current_user_web, get_current_user_api
from utils.validators import validate_cnpj, validate_email
from modules.companies.models import Company, CompanyDetails
from modules.api_keys.models import ApiKey
from pydantic import BaseModel

router = APIRouter()
templates = Jinja2Templates(directory="templates")

class StatusUpdateRequest(BaseModel):
    status: str

@router.get("/companies", response_class=HTMLResponse)
def list_companies(
    request: Request,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user_web)
):
    companies = db.query(Company).order_by(Company.created_at.desc()).all()
    return templates.TemplateResponse("companies/list.html", {
        "request": request,
        "companies": companies,
        "current_user": current_user,
        "active_page": "companies"
    })

@router.get("/companies/new", response_class=HTMLResponse)
def new_company_form(
    request: Request,
    current_user = Depends(get_current_user_web)
):
    return templates.TemplateResponse("companies/form.html", {
        "request": request,
        "current_user": current_user,
        "active_page": "companies"
    })

@router.post("/companies/new")
def create_company(
    request: Request,
    name: str = Form(...),
    fantasy_name: str = Form(None),
    cnpj: str = Form(...),
    email: str = Form(...),
    phone: str = Form(None),
    app_type: str = Form("both"),
    state_registration: str = Form(None),
    municipal_registration: str = Form(None),
    tax_regime: str = Form("simples"),
    business_type: str = Form("retail"),
    address: str = Form(None),
    city: str = Form(None),
    state: str = Form(None),
    zip_code: str = Form(None),
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user_web)
):
    # Validations
    if not validate_cnpj(cnpj):
        return templates.TemplateResponse("companies/form.html", {
            "request": request,
            "current_user": current_user,
            "active_page": "companies",
            "flash_message": "CNPJ Inválido. Digite um CNPJ de 14 dígitos com dígitos verificadores válidos.",
            "flash_type": "error"
        })
        
    if not validate_email(email):
        return templates.TemplateResponse("companies/form.html", {
            "request": request,
            "current_user": current_user,
            "active_page": "companies",
            "flash_message": "Endereço de e-mail inválido.",
            "flash_type": "error"
        })

    # Check unique CNPJ
    existing = db.query(Company).filter(Company.cnpj == cnpj).first()
    if existing:
        return templates.TemplateResponse("companies/form.html", {
            "request": request,
            "current_user": current_user,
            "active_page": "companies",
            "flash_message": "Empresa com este CNPJ já cadastrada no sistema.",
            "flash_type": "error"
        })

    # Create Company
    company = Company(
        name=name,
        fantasy_name=fantasy_name,
        cnpj=cnpj.replace(".", "").replace("/", "").replace("-", ""),
        email=email,
        phone=phone,
        app_type=app_type,
        status="active"
    )
    db.add(company)
    db.commit()
    db.refresh(company)

    # Create Details
    details = CompanyDetails(
        company_id=company.id,
        state_registration=state_registration,
        municipal_registration=municipal_registration,
        tax_regime=tax_regime,
        business_type=business_type,
        address=address,
        city=city,
        state=state,
        zip_code=zip_code
    )
    db.add(details)

    # Auto-generate initial access key
    api_key = ApiKey(
        company_id=company.id,
        key=f"cs_key_{secrets.token_hex(16)}",
        secret=f"cs_sec_{secrets.token_hex(24)}",
        name="Chave Inicial de Configuração"
    )
    db.add(api_key)
    
    db.commit()

    return RedirectResponse(
        url=f"/adm/companies/{company.id}",
        status_code=status.HTTP_303_SEE_OTHER
    )

@router.get("/companies/{id}", response_class=HTMLResponse)
def view_company(
    id: int,
    request: Request,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user_web)
):
    company = db.query(Company).filter(Company.id == id).first()
    if not company:
        raise HTTPException(status_code=404, detail="Empresa não encontrada")
    return templates.TemplateResponse("companies/detail.html", {
        "request": request,
        "company": company,
        "current_user": current_user,
        "active_page": "companies"
    })

@router.get("/companies/{id}/edit", response_class=HTMLResponse)
def edit_company_form(
    id: int,
    request: Request,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user_web)
):
    company = db.query(Company).filter(Company.id == id).first()
    if not company:
        raise HTTPException(status_code=404, detail="Empresa não encontrada")
    return templates.TemplateResponse("companies/form.html", {
        "request": request,
        "company": company,
        "details": company.details,
        "current_user": current_user,
        "active_page": "companies"
    })

@router.post("/companies/{id}/edit")
def edit_company(
    id: int,
    request: Request,
    name: str = Form(...),
    fantasy_name: str = Form(None),
    cnpj: str = Form(...),
    email: str = Form(...),
    phone: str = Form(None),
    app_type: str = Form("both"),
    state_registration: str = Form(None),
    municipal_registration: str = Form(None),
    tax_regime: str = Form("simples"),
    business_type: str = Form("retail"),
    address: str = Form(None),
    city: str = Form(None),
    state: str = Form(None),
    zip_code: str = Form(None),
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user_web)
):
    company = db.query(Company).filter(Company.id == id).first()
    if not company:
        raise HTTPException(status_code=404, detail="Empresa não encontrada")

    # Update company fields
    company.name = name
    company.fantasy_name = fantasy_name
    company.cnpj = cnpj.replace(".", "").replace("/", "").replace("-", "")
    company.email = email
    company.phone = phone
    company.app_type = app_type

    # Update details
    if not company.details:
        company.details = CompanyDetails(company_id=company.id)
    company.details.state_registration = state_registration
    company.details.municipal_registration = municipal_registration
    company.details.tax_regime = tax_regime
    company.details.business_type = business_type
    company.details.address = address
    company.details.city = city
    company.details.state = state
    company.details.zip_code = zip_code

    db.commit()

    return RedirectResponse(
        url=f"/adm/companies/{company.id}",
        status_code=status.HTTP_303_SEE_OTHER
    )

@router.patch("/api/companies/{id}/status")
def patch_company_status(
    id: int,
    payload: StatusUpdateRequest,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user_api)
):
    company = db.query(Company).filter(Company.id == id).first()
    if not company:
        return JSONResponse(status_code=404, content={"detail": "Empresa não encontrada"})
        
    company.status = payload.status
    db.commit()
    return {"id": company.id, "status": company.status}
