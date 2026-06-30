from fastapi import APIRouter, Depends, Request, status
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
from config.database import get_db
from config.security import get_current_user_web, get_current_user_api
from modules.companies.models import Company, CompanyModule
from modules.licenses.models import License
from modules.instances.models import Instance

router = APIRouter()
templates = Jinja2Templates(directory="templates")

def get_stats_data(db: Session):
    # Only fetch companies that have the 'coliseu-speed' module activated and active (Status=1)
    active_companies = db.query(Company)\
        .join(CompanyModule, Company.id == CompanyModule.company_id)\
        .filter(CompanyModule.module_slug == "coliseu-speed", CompanyModule.is_active == True, Company.status == 1)\
        .count()
        
    # Active licenses (devices) for speed companies (Status=1)
    active_licenses = db.query(License)\
        .join(Company)\
        .join(CompanyModule, Company.id == CompanyModule.company_id)\
        .filter(CompanyModule.module_slug == "coliseu-speed", CompanyModule.is_active == True, License.status == 1)\
        .count()
        
    # Revoked licenses (devices) (Status=2)
    expired_licenses = db.query(License)\
        .join(Company)\
        .join(CompanyModule, Company.id == CompanyModule.company_id)\
        .filter(CompanyModule.module_slug == "coliseu-speed", CompanyModule.is_active == True, License.status == 2)\
        .count()
        
    online_instances = db.query(Instance).filter(Instance.status == "online").count()
    
    return {
        "active_companies": active_companies,
        "active_licenses": active_licenses,
        "expired_licenses": expired_licenses,
        "online_instances": online_instances
    }

@router.get("/", response_class=HTMLResponse)
def get_dashboard(
    request: Request,
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user_web)
):
    stats = get_stats_data(db)
    
    # Fetch recent companies (last 5) filtered by speed module
    recent_companies = db.query(Company)\
        .join(CompanyModule, Company.id == CompanyModule.company_id)\
        .filter(CompanyModule.module_slug == "coliseu-speed", CompanyModule.is_active == True)\
        .order_by(Company.created_at.desc())\
        .limit(5)\
        .all()
    
    # Fetch recently accessed licenses (devices)
    recent_licenses = db.query(License)\
        .join(Company)\
        .join(CompanyModule, Company.id == CompanyModule.company_id)\
        .filter(CompanyModule.module_slug == "coliseu-speed", CompanyModule.is_active == True)\
        .order_by(License.last_access.desc())\
        .limit(5)\
        .all()
    
    return templates.TemplateResponse("dashboard/index.html", {
        "request": request,
        "stats": stats,
        "recent_companies": recent_companies,
        "expiring_licenses": recent_licenses, # map to recently active devices in the dashboard
        "current_user": current_user,
        "active_page": "dashboard"
    })

@router.get("/api/dashboard/stats")
def api_dashboard_stats(
    db: Session = Depends(get_db),
    current_user = Depends(get_current_user_api)
):
    stats = get_stats_data(db)
    return stats
