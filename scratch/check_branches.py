import requests
import json

url = "https://adminlicencas.coliseusistemas.com.br/internal/companies/1e40d65f-4319-4c68-ae13-66223820c095/branches"
headers = {
    "X-Internal-Api-Key": "Coliseu2026!IdentitySuperSecretKeyOauth20"
}

resp = requests.get(url, headers=headers)
print("Status:", resp.status_code)
try:
    print(json.dumps(resp.json(), indent=2))
except Exception as e:
    print(resp.text)
