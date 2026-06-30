from modules.auth.models import User
from config.security import get_password_hash, create_access_token
from modules.companies.models import Company
from modules.licenses.models import License
from datetime import datetime, timedelta

def test_license_activation_and_validation(client, db_session):
    # Seed admin user
    hashed_pwd = get_password_hash("secret123")
    user = User(email="admin@coliseu.com.br", password_hash=hashed_pwd, full_name="Admin", is_active=True)
    db_session.add(user)
    
    # Seed active company
    company = Company(name="Empresa Licenciada", cnpj="60701190000104", email="contato@empresa.com", status="active")
    db_session.add(company)
    db_session.commit()
    
    # Authenticate client
    token = create_access_token({"sub": "admin@coliseu.com.br"})
    client.cookies.set("session_token", token)
    
    # Post activation with mock license key (starting with "MOCK-")
    response = client.post("/licenses/new", data={
        "company_id": company.id,
        "license_key": "MOCK-SPEED-VAL-123",
        "product_type": "coliseu_speed"
    }, follow_redirects=False)
    
    assert response.status_code == 303 # Redirects back to details
    
    # Check db insertion
    lic = db_session.query(License).filter(License.license_key == "MOCK-SPEED-VAL-123").first()
    assert lic is not None
    assert lic.status == "active"
    assert lic.max_users == 10
    
    # Call JSON validate endpoint
    auth_header = {"Authorization": f"Bearer {token}"}
    response_api = client.get(f"/api/companies/{company.id}/licenses/{lic.id}/validate", headers=auth_header)
    assert response_api.status_code == 200
    assert response_api.json()["valid"] == True
    
    # Expire license manually and validate
    lic.expiration_date = datetime.utcnow() - timedelta(days=1)
    db_session.commit()
    
    response_api_expired = client.get(f"/api/companies/{company.id}/licenses/{lic.id}/validate", headers=auth_header)
    assert response_api_expired.status_code == 200
    assert response_api_expired.json()["valid"] == False
    assert response_api_expired.json()["status"] == "expired"
