def test_unauthenticated_view_redirects_to_login(client):
    # Fetching dashboard without cookie should redirect
    response = client.get("/", follow_redirects=False)
    assert response.status_code == 307
    assert response.headers["location"] == "/login"

def test_login_page_renders_successfully(client):
    response = client.get("/login")
    assert response.status_code == 200
    assert "Login Força de Vendas" in response.text

def test_login_flow_redirects_to_branch_selection(client):
    # Log in as mock representative
    payload = {"username": "vendedor", "password": "any_password"}
    response = client.post("/auth/login", data=payload, follow_redirects=False)
    
    assert response.status_code == 303
    assert response.headers["location"] == "/select-branch"
    assert "rep_token" in response.cookies
