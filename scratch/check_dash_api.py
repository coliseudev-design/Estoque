import requests
import json

base_url = "https://dashboard.coliseusistemas.com.br"
headers = {
    "X-Internal-Key": "COL-YUZA-9WSK-TN88",
    "X-Tenant-Id": "1e40d65f-4319-4c68-ae13-66223820c095"
}

# 1. Check health
try:
    resp = requests.get(f"{base_url}/health", timeout=5)
    print("Health Status:", resp.status_code)
    print("Health Body:", resp.text)
except Exception as e:
    print("Health Error:", e)

# 2. Check if we can introspect config or stats or something
try:
    resp = requests.get(f"{base_url}/api/admin/config", headers={"x-api-key": "COL-YUZA-9WSK-TN88"}, timeout=5)
    print("Admin Config Status:", resp.status_code)
    print("Admin Config Body:", resp.text)
except Exception as e:
    print("Admin Config Error:", e)
