import requests
import json

base_url = "https://dashboard.coliseusistemas.com.br"
headers = {
    "X-Internal-Key": "COL-YUZA-9WSK-TN88",
    "X-Tenant-Id": "1e40d65f-4319-4c68-ae13-66223820c095",
    "Content-Type": "application/json"
}

# Try GET /internal/sync/dash_vendas
try:
    resp = requests.get(f"{base_url}/internal/sync/dash_vendas", headers=headers, timeout=5)
    print("GET status:", resp.status_code)
    print("GET body:", resp.text)
except Exception as e:
    print("GET error:", e)

# Try POST /internal/sync/dash_vendas with empty rows
try:
    resp = requests.post(f"{base_url}/internal/sync/dash_vendas", headers=headers, json={"rows": []}, timeout=5)
    print("POST status:", resp.status_code)
    print("POST body:", resp.text)
except Exception as e:
    print("POST error:", e)
