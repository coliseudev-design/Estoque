from fastapi import APIRouter, Depends, Request, Form, status, HTTPException
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
import secrets
import uuid
from config.database import get_db
from config.security import get_current_user_web, get_current_user_api
from utils.validators import validate_cnpj, validate_email
from modules.companies.models import Company, CompanyDetails, CompanyModule, Branch
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
    # Only fetch companies that have the 'coliseu-speed' module activated and active (Status=1)
    companies = db.query(Company)\
        .join(CompanyModule, Company.id == CompanyModule.company_id)\
        .filter(CompanyModule.module_slug == "coliseu-speed", CompanyModule.is_active == True)\
        .order_by(Company.created_at.desc())\
        .all()

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

    # Create Company with a new GUID
    company_id = str(uuid.uuid4())
    company = Company(
        id=company_id,
        name=name,
        email=email,
        status=1 # 1=Active
    )
    db.add(company)
    
    # Auto-activate the speed module in company_modules
    company_module = CompanyModule(
        company_id=company_id,
        module_slug="coliseu-speed",
        is_active=True
    )
    db.add(company_module)

    # Create default Branch and assign CNPJ to it
    branch = Branch(
        id=str(uuid.uuid4()),
        company_id=company_id,
        name="Matriz",
        cnpj=cnpj.replace(".", "").replace("/", "").replace("-", ""),
        is_default=True
    )
    db.add(branch)

    # Create Details
    details = CompanyDetails(
        company_id=company_id,
        fantasy_name=fantasy_name,
        phone=phone,
        app_type=app_type,
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
        company_id=company_id,
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
    id: str,
    request: Request,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user_web)
):
    company = db.query(Company).filter(Company.id == id).first()
    if not company:
        raise HTTPException(status_code=404, detail="Empresa não encontrada")
        
    # Auto-initialize company details if missing (imported company from licencas)
    if not company.details:
        company.details = CompanyDetails(company_id=company.id)
        db.add(company.details)
        db.commit()
        db.refresh(company)

    return templates.TemplateResponse("companies/detail.html", {
        "request": request,
        "company": company,
        "current_user": current_user,
        "active_page": "companies"
    })

@router.get("/companies/{id}/edit", response_class=HTMLResponse)
def edit_company_form(
    id: str,
    request: Request,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user_web)
):
    company = db.query(Company).filter(Company.id == id).first()
    if not company:
        raise HTTPException(status_code=404, detail="Empresa não encontrada")
        
    if not company.details:
        company.details = CompanyDetails(company_id=company.id)
        db.add(company.details)
        db.commit()
        db.refresh(company)

    return templates.TemplateResponse("companies/form.html", {
        "request": request,
        "company": company,
        "details": company.details,
        "current_user": current_user,
        "active_page": "companies"
    })

@router.post("/companies/{id}/edit")
def edit_company(
    id: str,
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

    # Update central company profile
    company.name = name
    company.email = email

    # Update or create default branch for CNPJ
    default_branch = next((b for b in company.branches if b.is_default), None)
    clean_cnpj = cnpj.replace(".", "").replace("/", "").replace("-", "")
    if default_branch:
        default_branch.cnpj = clean_cnpj
    else:
        new_branch = Branch(
            id=str(uuid.uuid4()),
            company_id=company.id,
            name="Matriz",
            cnpj=clean_cnpj,
            is_default=True
        )
        db.add(new_branch)

    # Update details
    if not company.details:
        company.details = CompanyDetails(company_id=company.id)
        
    company.details.fantasy_name = fantasy_name
    company.details.phone = phone
    company.details.app_type = app_type
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
    id: str,
    payload: StatusUpdateRequest,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user_api)
):
    company = db.query(Company).filter(Company.id == id).first()
    if not company:
        return JSONResponse(status_code=404, content={"detail": "Empresa não encontrada"})
        
    # status codes: 1 = Active, 2 = Suspended / Inactive in legacy backend
    company.status = 1 if payload.status == "active" else 2
    db.commit()
    return {"id": company.id, "status": "active" if company.status == 1 else "inactive"}
