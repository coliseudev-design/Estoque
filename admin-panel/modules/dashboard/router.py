from fastapi import APIRouter, Depends, Request, status
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
from config.database import get_db
from config.security import get_current_user_web, get_current_user_api
from modules.companies.models import Company
from modules.licenses.models import License
from modules.instances.models import Instance

router = APIRouter()
templates = Jinja2Templates(directory="templates")

def get_stats_data(db: Session):
    now = datetime.utcnow()
    active_companies = db.query(Company).filter(Company.status == "active").count()
    active_licenses = db.query(License).filter(License.status == "active").count()
    expired_licenses = db.query(License).filter(
        (License.status == "expired") | (License.expiration_date < now)
    ).count()
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
    
    # Fetch recent companies (last 5)
    recent_companies = db.query(Company).order_by(Company.created_at.desc()).limit(5).all()
    
    # Fetch expiring licenses (expiring in next 30 days)
    now = datetime.utcnow()
    thirty_days_later = now + timedelta(days=30)
    expiring_licenses = db.query(License).filter(
        License.status == "active",
        License.expiration_date > now,
        License.expiration_date <= thirty_days_later
    ).order_by(License.expiration_date.asc()).limit(5).all()
    
    return templates.TemplateResponse("dashboard/index.html", {
        "request": request,
        "stats": stats,
        "recent_companies": recent_companies,
        "expiring_licenses": expiring_licenses,
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
