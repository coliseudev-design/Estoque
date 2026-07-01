from fastapi import APIRouter, Depends, Request, status
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
from config.database import get_db, get_identity_db
from config.security import get_current_user_web, get_current_user_api
from modules.companies.models import Company, CompanyDetails, CompanyModule
from modules.licenses.models import License
from modules.instances.models import Instance

router = APIRouter()
templates = Jinja2Templates(directory="templates")

def get_stats_data(local_db: Session, identity_db: Session):
    # Active companies from central DB (Status=0)
    active_companies = identity_db.query(Company)\
        .join(CompanyModule, Company.id == CompanyModule.company_id)\
        .filter(CompanyModule.module_slug.in_(["coliseu-speed", "coliseuspeed"]), CompanyModule.is_active == True, Company.status == 0)\
        .count()
        
    # Active licenses (devices) from central DB (Status=0)
    active_licenses = identity_db.query(License)\
        .join(Company)\
        .join(CompanyModule, Company.id == CompanyModule.company_id)\
        .filter(CompanyModule.module_slug.in_(["coliseu-speed", "coliseuspeed"]), CompanyModule.is_active == True, License.status_code == 0)\
        .count()
        
    # Revoked licenses (devices) from central DB (Status=2)
    expired_licenses = identity_db.query(License)\
        .join(Company)\
        .join(CompanyModule, Company.id == CompanyModule.company_id)\
        .filter(CompanyModule.module_slug.in_(["coliseu-speed", "coliseuspeed"]), CompanyModule.is_active == True, License.status_code == 2)\
        .count()
        
    # Online instances from local DB
    online_instances = local_db.query(Instance).filter(Instance.status == "online").count()
    
    return {
        "active_companies": active_companies,
        "active_licenses": active_licenses,
        "expired_licenses": expired_licenses,
        "online_instances": online_instances
    }

@router.get("/", response_class=HTMLResponse)
def get_dashboard(
    request: Request,
    local_db: Session = Depends(get_db),
    identity_db: Session = Depends(get_identity_db),
    current_user = Depends(get_current_user_web)
):
    stats = get_stats_data(local_db, identity_db)
    
    # Fetch recent companies from central DB
    recent_companies = identity_db.query(Company)\
        .join(CompanyModule, Company.id == CompanyModule.company_id)\
        .filter(CompanyModule.module_slug.in_(["coliseu-speed", "coliseuspeed"]), CompanyModule.is_active == True)\
        .order_by(Company.created_at.desc())\
        .limit(5)\
        .all()
        
    # Load details locally
    for company in recent_companies:
        company.details = local_db.query(CompanyDetails).filter(CompanyDetails.company_id == company.id).first()
    
    # Fetch recently accessed licenses (devices) from central DB
    recent_licenses = identity_db.query(License)\
        .join(Company)\
        .join(CompanyModule, Company.id == CompanyModule.company_id)\
        .filter(CompanyModule.module_slug.in_(["coliseu-speed", "coliseuspeed"]), CompanyModule.is_active == True)\
        .order_by(License.last_access.desc())\
        .limit(5)\
        .all()
    
    return templates.TemplateResponse("dashboard/index.html", {
        "request": request,
        "stats": stats,
        "recent_companies": recent_companies,
        "expiring_licenses": recent_licenses,
        "current_user": current_user,
        "active_page": "dashboard"
    })

@router.get("/api/dashboard/stats")
def api_dashboard_stats(
    local_db: Session = Depends(get_db),
    identity_db: Session = Depends(get_identity_db),
    current_user = Depends(get_current_user_api)
):
    stats = get_stats_data(local_db, identity_db)
    return stats
