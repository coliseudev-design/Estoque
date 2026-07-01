from fastapi import FastAPI, Depends, Request, status
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.orm import Session
import os

from config.config import settings
from config.database import engine, Base, SessionLocal, get_db
from config.security import get_password_hash

# Routers
from modules.auth.router import router as auth_router
from modules.companies.router import router as companies_router
from modules.licenses.router import router as licenses_router
from modules.integrations.router import router as integrations_router
from modules.instances.router import router as instances_router
from modules.api_keys.router import router as api_keys_router
from modules.dashboard.router import router as dashboard_router

# Models (import to trigger register with Base.metadata)
from modules.auth.models import User
from modules.companies.models import Company, CompanyDetails
from modules.licenses.models import License
from modules.integrations.models import ApiIntegration
from modules.instances.models import Instance
from modules.api_keys.models import ApiKey

# Create Tables
Base.metadata.create_all(bind=engine)

app = FastAPI(title=settings.PROJECT_NAME)

# CORS Middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount Static Assets
app.mount("/adm/static", StaticFiles(directory="static"), name="static")

# Include Routers with prefix /adm
app.include_router(auth_router, prefix="/adm")
app.include_router(companies_router, prefix="/adm")
app.include_router(licenses_router, prefix="/adm")
app.include_router(integrations_router, prefix="/adm")
app.include_router(instances_router, prefix="/adm")
app.include_router(api_keys_router, prefix="/adm")
app.include_router(dashboard_router, prefix="/adm")

# Seed Initial Admin Account
@app.on_event("startup")
def seed_admin_user():
    db = SessionLocal()
    try:
        admin_email = settings.SEED_ADMIN_EMAIL
        admin_password = settings.SEED_ADMIN_PASSWORD
        
        # Check if user exists
        user = db.query(User).filter(User.email == admin_email).first()
        if not user:
            print(f"Seeding default administrator: {admin_email}")
            admin = User(
                email=admin_email,
                password_hash=get_password_hash(admin_password),
                full_name="Coliseu Admin",
                is_active=True,
                role=0
            )
            db.add(admin)
        else:
            print(f"Ensuring default administrator credentials: {admin_email}")
            user.password_hash = get_password_hash(admin_password)
            user.is_active = True
            user.role = 0
        db.commit()
    finally:
        db.close()

# Root route logic
@app.middleware("http")
async def check_session_routing(request: Request, call_next):
    # If requests are made to root/views and session_token is not present, redirect to login
    # except static folder, login routes, forgot password
    path = request.url.path
    if path.startswith("/adm/static") or path in ["/adm/login", "/adm/auth/login", "/adm/forgot-password", "/adm/auth/forgot-password", "/adm/auth/logout"]:
        return await call_next(request)
        
    token = request.cookies.get("session_token")
    if not token and not path.startswith("/adm/api"):
        return RedirectResponse(url="/adm/login", status_code=status.HTTP_307_TEMPORARY_REDIRECT)
        
    return await call_next(request)
