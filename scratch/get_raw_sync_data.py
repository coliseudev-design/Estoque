import requests
import json

headers = {
    "api-key": "COL-NZ2Q-U4ZD-CDDH",
    "X-Company-Id": "1e40d65f-4319-4c68-ae13-66223820c095"
}

# Try seller 105
r1 = requests.get("https://licencas.coliseusistemas.com.br/api/sync/performance?sellerId=105", headers=headers)
print("Performance Status:", r1.status_code)
try:
    print("Performance Sample:", json.dumps(r1.json(), indent=2))
except Exception as e:
    print(r1.text)

r2 = requests.get("https://licencas.coliseusistemas.com.br/api/sync/sales-rankings?sellerId=105", headers=headers)
print("Sales Rankings Status:", r2.status_code)
try:
    print("Rankings Sample:", json.dumps(r2.json(), indent=2))
except Exception as e:
    print(r2.text)
