import requests
import json

url = "https://licencas.coliseusistemas.com.br/api/orders/pending?confirmedSince=2026-05-19T00:00:00.000Z"
headers = {
    "api-key": "COL-NZ2Q-U4ZD-CDDH",
    "X-Company-Id": "1e40d65f-4319-4c68-ae13-66223820c095"
}

resp = requests.get(url, headers=headers)
print("Status:", resp.status_code)
try:
    print(json.dumps(resp.json(), indent=2))
except Exception as e:
    print(resp.text)
