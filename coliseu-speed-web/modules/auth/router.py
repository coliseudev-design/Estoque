from fastapi import APIRouter, Depends, Request, Form, Response, status, HTTPException
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
import httpx
from utils.api_client import api_client
from utils.admin_client import admin_client
from config.config import settings

router = APIRouter()
templates = Jinja2Templates(directory="templates")

@router.get("/login", response_class=HTMLResponse)
def login_view(request: Request):
    # Check if already logged in
    token = request.cookies.get("rep_token")
    branch = request.cookies.get("rep_branch_id")
    if token and branch:
        return RedirectResponse(url="/", status_code=status.HTTP_302_FOUND)
        
    company_name = request.cookies.get("rep_company_name")
    company_id = request.cookies.get("rep_company_id")
    api_key = request.cookies.get("rep_api_key")
    
    return templates.TemplateResponse("auth/login.html", {
        "request": request,
        "company_name": company_name,
        "company_id": company_id,
        "is_configured": bool(api_key)
    })

@router.get("/setup-company", response_class=HTMLResponse)
def setup_company_view(request: Request):
    return templates.TemplateResponse("auth/setup_company.html", {"request": request})

@router.post("/setup-company")
async def post_setup_company(
    response: Response,
    request: Request,
    api_key: str = Form(...)
):
    api_key = api_key.strip()
    if not api_key:
        return templates.TemplateResponse("auth/setup_company.html", {
            "request": request,
            "error_message": "A Chave de Acesso é obrigatória."
        })

    # Query admin-panel to resolve company details via API Key
    try:
        async with httpx.AsyncClient(timeout=6.0) as client:
            url = f"{settings.ADMIN_PANEL_URL}/adm/api/companies/lookup-by-key"
            res = await client.post(url, json={"api_key": api_key})
            if res.status_code == 200:
                data = res.json()
                if data.get("success", False):
                    # Set cookies and redirect to login
                    redirect = RedirectResponse(url="/login", status_code=status.HTTP_303_SEE_OTHER)
                    redirect.set_cookie("rep_api_key", api_key, max_age=31536000, httponly=True)
                    redirect.set_cookie("rep_company_id", data["company_id"], max_age=31536000, httponly=True)
                    redirect.set_cookie("rep_company_name", data["company_name"], max_age=31536000, httponly=True)
                    return redirect
                else:
                    error = data.get("detail", "Chave inválida.")
            else:
                error = "Chave de acesso inválida ou inativa no painel central."
    except Exception as e:
        print(f"[SetupCompany] Lookup failed: {e}")
        error = "Erro ao conectar com o servidor de licenciamento."

    return templates.TemplateResponse("auth/setup_company.html", {
        "request": request,
        "error_message": error
    })

@router.post("/auth/login")
async def post_login(
    response: Response,
    request: Request,
    username: str = Form(...),
    password: str = Form(...)
):
    api_key = request.cookies.get("rep_api_key")
    company_id = request.cookies.get("rep_company_id")
    
    if not api_key:
        return RedirectResponse(url="/setup-company", status_code=status.HTTP_303_SEE_OTHER)

    # 1. Authenticate Rep on Middleware
    auth_res = await api_client.authenticate_rep(username, password, api_key=api_key)
    if not auth_res.get("success", False):
        return templates.TemplateResponse("auth/login.html", {
            "request": request, 
            "error_message": auth_res.get("message", "Falha de login."),
            "company_name": request.cookies.get("rep_company_name"),
            "is_configured": True
        })
        
    # 2. Check Company License status on Admin Panel
    lic_res = await admin_client.get_license_status(company_id=company_id)
    if not lic_res.get("valid", False):
        return templates.TemplateResponse("auth/login.html", {
            "request": request,
            "error_message": "Acesso Bloqueado. A licença deste inquilino está inativa ou expirada. Contate o administrador.",
            "company_name": request.cookies.get("rep_company_name"),
            "is_configured": True
        })

    # 3. Store rep token in cookie and redirect to Select Branch
    redirect = RedirectResponse(url="/select-branch", status_code=status.HTTP_303_SEE_OTHER)
    redirect.set_cookie("rep_token", auth_res["token"], httponly=True)
    redirect.set_cookie("rep_name", auth_res.get("rep_name", "Vendedor"), httponly=True)
    redirect.set_cookie("rep_seller_id", auth_res.get("seller_id", ""), httponly=True)
    return redirect

@router.get("/select-branch", response_class=HTMLResponse)
async def select_branch_view(request: Request):
    token = request.cookies.get("rep_token")
    api_key = request.cookies.get("rep_api_key")
    if not token or not api_key:
        return RedirectResponse(url="/login")
        
    branches = await api_client.get_branches(token, api_key=api_key)
    return templates.TemplateResponse("auth/select_branch.html", {
        "request": request,
        "branches": branches
    })

@router.post("/auth/select-branch")
async def post_select_branch(
    request: Request,
    branch_id: str = Form(...),
    db_session = None
):
    token = request.cookies.get("rep_token")
    api_key = request.cookies.get("rep_api_key")
    # Fetch target branch name for visual branding
    branches = await api_client.get_branches(token, api_key=api_key)
    branch = next((b for b in branches if b["id"] == branch_id), None)
    branch_name = branch["name"] if branch else "Filial Padrão"

    redirect = RedirectResponse(url="/", status_code=status.HTTP_303_SEE_OTHER)
    redirect.set_cookie("rep_branch_id", branch_id, httponly=True)
    redirect.set_cookie("rep_branch_name", branch_name, httponly=True)
    return redirect

@router.get("/auth/logout")
def logout():
    redirect = RedirectResponse(url="/login", status_code=status.HTTP_302_FOUND)
    redirect.delete_cookie("rep_token")
    redirect.delete_cookie("rep_name")
    redirect.delete_cookie("rep_branch_id")
    redirect.delete_cookie("rep_branch_name")
    return redirect
