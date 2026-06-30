from fastapi import APIRouter, Depends, Request, Form, Response, status
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session
from config.database import get_db
from config.security import verify_password, create_access_token, get_password_hash
from modules.auth.models import User
import os

router = APIRouter()
templates = Jinja2Templates(directory="templates")

@router.get("/login", response_class=HTMLResponse)
def get_login(request: Request):
    # If already logged in, redirect to index
    token = request.cookies.get("session_token")
    if token:
        return RedirectResponse(url="/adm/", status_code=status.HTTP_302_FOUND)
    return templates.TemplateResponse("auth/login.html", {"request": request})

@router.post("/auth/login")
def post_login(
    response: Response,
    request: Request,
    email: str = Form(...),
    password: str = Form(...),
    db: Session = Depends(get_db)
):
    user = db.query(User).filter(User.email == email, User.is_active == True).first()
    if not user or not verify_password(password, user.password_hash):
        return templates.TemplateResponse(
            "auth/login.html", 
            {"request": request, "error_message": "E-mail ou senha incorretos."}
        )
    
    # Generate token
    token = create_access_token({"sub": user.email})
    
    # Redirect to home and set cookie
    redirect = RedirectResponse(url="/adm/", status_code=status.HTTP_303_SEE_OTHER)
    redirect.set_cookie(
        key="session_token",
        value=token,
        httponly=True,
        max_age=3600, # 1 hour
        samesite="lax",
        secure=False # set true in HTTPS production
    )
    return redirect

@router.get("/auth/logout")
def logout():
    redirect = RedirectResponse(url="/adm/login", status_code=status.HTTP_302_FOUND)
    redirect.delete_cookie("session_token")
    return redirect

@router.get("/forgot-password", response_class=HTMLResponse)
def get_forgot_password(request: Request):
    return templates.TemplateResponse("auth/forgot-password.html", {"request": request})

@router.post("/auth/forgot-password")
def post_forgot_password(request: Request, email: str = Form(...), db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == email).first()
    msg = "Se o e-mail estiver registrado, você receberá instruções de redefinição."
    # Simulate email trigger
    return templates.TemplateResponse("auth/forgot-password.html", {
        "request": request, 
        "success_message": msg
    })
