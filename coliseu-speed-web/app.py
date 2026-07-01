from fastapi import FastAPI, Depends, Request, status
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from config.config import settings

# Routers
from modules.auth.router import router as auth_router
from modules.dashboard.router import router as dashboard_router
from modules.catalog.router import router as catalog_router
from modules.orders.router import router as orders_router
from modules.customers.router import router as customers_router
from modules.performance.router import router as performance_router
from modules.sync.router import router as sync_router
from modules.settings.router import router as settings_router

app = FastAPI(title=settings.PROJECT_NAME)

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount Static assets
app.mount("/static", StaticFiles(directory="static"), name="static")

# Include Routers
app.include_router(auth_router)
app.include_router(dashboard_router)
app.include_router(catalog_router)
app.include_router(orders_router)
app.include_router(customers_router)
app.include_router(performance_router)
app.include_router(sync_router)
app.include_router(settings_router)

# Route checks session middleware
@app.middleware("http")
async def check_rep_session_routing(request: Request, call_next):
    path = request.url.path
    # Ignore static files, login views, setup views, and auth processors
    if path.startswith("/static") or path in ["/login", "/auth/login", "/auth/logout", "/select-branch", "/auth/select-branch", "/setup-company"]:
        return await call_next(request)
        
    token = request.cookies.get("rep_token")
    if not token and not path.startswith("/api"):
        return RedirectResponse(url="/login", status_code=status.HTTP_307_TEMPORARY_REDIRECT)
        
    branch = request.cookies.get("rep_branch_id")
    if token and not branch and path != "/select-branch" and not path.startswith("/api"):
        return RedirectResponse(url="/select-branch", status_code=status.HTTP_307_TEMPORARY_REDIRECT)

    return await call_next(request)
