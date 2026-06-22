import requests
import json

headers = {
    "api-key": "COL-NZ2Q-U4ZD-CDDH",
    "X-Company-Id": "1e40d65f-4319-4c68-ae13-66223820c095",
    "X-Branch-Id": "7508465a-4c84-4a1f-83e2-4a9313f805d9"
}

# Try seller 105
url = "https://licencas.coliseusistemas.com.br/api/sync/performance?sellerId=105&month=5&year=2026"
r1 = requests.get(url, headers=headers)
print("Performance Status:", r1.status_code)
try:
    print("Performance Result:", json.dumps(r1.json(), indent=2))
except Exception as e:
    print(r1.text)

url_force = "https://licencas.coliseusistemas.com.br/api/sync/performance?sellerId=105&month=5&year=2026&forceRefresh=true"
r2 = requests.get(url_force, headers=headers)
print("Performance Status (force):", r2.status_code)
try:
    print("Performance Result (force):", json.dumps(r2.json(), indent=2))
except Exception as e:
    print(r2.text)

