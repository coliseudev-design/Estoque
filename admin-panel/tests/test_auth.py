from modules.auth.models import User
from config.security import get_password_hash

def test_unauthenticated_redirect_to_login(client):
    # Any view request without cookie should redirect to login
    response = client.get("/", follow_redirects=False)
    assert response.status_code == 307
    assert response.headers["location"] == "/login"

def test_login_page_renders_successfully(client):
    response = client.get("/login")
    assert response.status_code == 200
    assert "Login Administrador" in response.text

def test_login_flow_credentials_check(client, db_session):
    # Seed a user
    hashed_pwd = get_password_hash("secret123")
    user = User(
        email="test_admin@coliseu.com.br",
        password_hash=hashed_pwd,
        full_name="Test User",
        is_active=True
    )
    db_session.add(user)
    db_session.commit()
    
    # Try logging in with wrong password
    payload_wrong = {"email": "test_admin@coliseu.com.br", "password": "wrong_password"}
    response = client.post("/auth/login", data=payload_wrong)
    assert response.status_code == 200
    assert "E-mail ou senha incorretos." in response.text
    
    # Log in with correct credentials
    payload_correct = {"email": "test_admin@coliseu.com.br", "password": "secret123"}
    response = client.post("/auth/login", data=payload_correct, follow_redirects=False)
    assert response.status_code == 303 # Redirects to home on success
    assert response.headers["location"] == "/"
    assert "session_token" in response.cookies
