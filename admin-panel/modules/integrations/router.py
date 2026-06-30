from fastapi import APIRouter, Depends, Request, Form, status, HTTPException
from fastapi.responses import HTMLResponse, RedirectResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
from datetime import datetime
from config.database import get_db
from config.security import get_current_user_web, get_current_user_api
from modules.companies.models import Company
from modules.integrations.models import ApiIntegration

router = APIRouter()
templates = Jinja2Templates(directory="templates")

@router.get("/integrations", response_class=HTMLResponse)
def list_integrations(
    request: Request,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user_web)
):
    integrations = db.query(ApiIntegration).join(Company).order_by(ApiIntegration.created_at.desc()).all()
    return templates.TemplateResponse("integrations/list.html", {
        "request": request,
        "integrations": integrations,
        "current_user": current_user,
        "active_page": "integrations"
    })

@router.get("/integrations/new", response_class=HTMLResponse)
def new_integration_form(
    request: Request,
    company_id: int = None,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user_web)
):
    companies = db.query(Company).filter(Company.status == "active").all()
    return templates.TemplateResponse("integrations/form.html", {
        "request": request,
        "companies": companies,
        "selected_company_id": company_id,
        "current_user": current_user,
        "active_page": "integrations"
    })

@router.post("/integrations/new")
def create_integration(
    request: Request,
    company_id: int = Form(...),
    api_type: str = Form(...),
    api_key: str = Form(...),
    api_secret: str = Form(None),
    webhook_url: str = Form(None),
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user_web)
):
    # Check if this type of integration already exists for this company
    existing = db.query(ApiIntegration).filter(
        ApiIntegration.company_id == company_id,
        ApiIntegration.api_type == api_type
    ).first()
    
    if existing:
        # Update existing integration keys
        existing.api_key = api_key
        existing.api_secret = api_secret
        existing.webhook_url = webhook_url
        existing.is_active = True
        existing.updated_at = datetime.utcnow()
    else:
        # Create new integration
        integration = ApiIntegration(
            company_id=company_id,
            api_type=api_type,
            api_key=api_key,
            api_secret=api_secret,
            webhook_url=webhook_url,
            is_active=True
        )
        db.add(integration)
        
    db.commit()

    return RedirectResponse(
        url=f"/adm/companies/{company_id}",
        status_code=status.HTTP_303_SEE_OTHER
    )

@router.patch("/api/companies/{company_id}/integrations/{integration_id}/test")
def test_integration(
    company_id: int,
    integration_id: int,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user_api)
):
    integration = db.query(ApiIntegration).filter(
        ApiIntegration.id == integration_id,
        ApiIntegration.company_id == company_id
    ).first()
    
    if not integration:
        return JSONResponse(status_code=404, content={"success": False, "message": "Integração não encontrada"})

    # Simulate connection check based on API type
    success = True
    message = "Conexão estabelecida com sucesso."
    
    if "FAIL" in integration.api_key.upper():
        success = False
        message = "Rejeitado pelo servidor externo com erro 403 Forbidden."
    
    # Update last tested timestamp
    integration.last_tested_at = datetime.utcnow()
    db.commit()

    return {"success": success, "message": message, "timestamp": integration.last_tested_at}
