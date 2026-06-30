from modules.auth.models import User
from config.security import get_password_hash, create_access_token
from modules.companies.models import Company
from utils.validators import validate_cnpj

def test_cnpj_validator_digits():
    # Valid CNPJ examples (standard test CNPJ digits)
    assert validate_cnpj("11222333000100") == False # obvious invalid repeating format
    assert validate_cnpj("60701190000104") == True # valid check
    assert validate_cnpj("00000000000000") == False # invalid zeroes

def test_company_creation_requires_auth(client):
    response = client.post("/companies/new", data={
        "name": "Nova Empresa Ltda",
        "cnpj": "60701190000104",
        "email": "contato@empresa.com"
    })
    assert response.status_code == 307 # Redirects to login

def test_company_onboarding_flow(client, db_session):
    # Seed admin user and login to get cookie
    hashed_pwd = get_password_hash("secret123")
    user = User(
        email="admin@coliseu.com.br",
        password_hash=hashed_pwd,
        full_name="Admin",
        is_active=True
    )
    db_session.add(user)
    db_session.commit()
    
    token = create_access_token({"sub": "admin@coliseu.com.br"})
    client.cookies.set("session_token", token)
    
    # Create company with invalid CNPJ first
    response = client.post("/companies/new", data={
        "name": "Empresa Invalida",
        "cnpj": "123",
        "email": "contato@empresa.com",
        "tax_regime": "simples",
        "business_type": "retail"
    })
    assert "CNPJ Inválido" in response.text
    
    # Create company with valid CNPJ
    response = client.post("/companies/new", data={
        "name": "Coliseu Cliente Exemplo Ltda",
        "fantasy_name": "Cliente Exemplo",
        "cnpj": "60.701.190/0001-04",
        "email": "suporte@clienteexemplo.com.br",
        "phone": "(11) 98888-7777",
        "app_type": "both",
        "state_registration": "111222333",
        "municipal_registration": "444555",
        "tax_regime": "simples",
        "business_type": "retail",
        "address": "Av Paulista 1000",
        "city": "São Paulo",
        "state": "SP",
        "zip_code": "01310-100"
    }, follow_redirects=False)
    
    assert response.status_code == 303 # redirects to detail view on success
    
    # Verify database insertion
    comp = db_session.query(Company).filter(Company.name == "Coliseu Cliente Exemplo Ltda").first()
    assert comp is not None
    assert comp.cnpj == "60701190000104"
    assert comp.details.address == "Av Paulista 1000"
    
    # Check that an API key was auto-generated
    assert len(comp.api_keys) == 1
    assert comp.api_keys[0].name == "Chave Inicial de Configuração"
