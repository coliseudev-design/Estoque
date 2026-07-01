from fastapi import APIRouter, Depends, Request, Form, Response, status
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from utils.api_client import api_client
from utils.admin_client import admin_client

router = APIRouter()
templates = Jinja2Templates(directory="templates")

@router.get("/login", response_class=HTMLResponse)
def login_view(request: Request):
    # Check if already logged in
    token = request.cookies.get("rep_token")
    branch = request.cookies.get("rep_branch_id")
    if token and branch:
        return RedirectResponse(url="/", status_code=status.HTTP_302_FOUND)
    return templates.TemplateResponse("auth/login.html", {"request": request})

@router.post("/auth/login")
async def post_login(
    response: Response,
    request: Request,
    username: str = Form(...),
    password: str = Form(...)
):
    # 1. Authenticate Rep on Middleware
    auth_res = await api_client.authenticate_rep(username, password)
    if not auth_res.get("success", False):
        return templates.TemplateResponse("auth/login.html", {
            "request": request, 
            "error_message": auth_res.get("message", "Falha de login.")
        })
        
    # 2. Check Company License status on Admin Panel
    lic_res = await admin_client.get_license_status()
    if not lic_res.get("valid", False):
        return templates.TemplateResponse("auth/login.html", {
            "request": request,
            "error_message": "Acesso Bloqueado. A licença deste inquilino está inativa ou expirada. Contate o administrador."
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
    if not token:
        return RedirectResponse(url="/login")
        
    branches = await api_client.get_branches(token)
    return templates.TemplateResponse("auth/select_branch.html", {
        "request": request,
        "branches": branches
    })

@router.post("/auth/select-branch")
async def post_select_branch(
    branch_id: str = Form(...),
    db_session = None
):
    # Fetch target branch name for visual branding
    branches = await api_client.get_branches("token")
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
