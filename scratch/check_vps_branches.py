import urllib.request
import json

url = "https://adminlicencas.coliseusistemas.com.br/internal/companies/1e40d65f-4319-4c68-ae13-66223820c095/branches"
req = urllib.request.Request(url)
req.add_header("X-Internal-Api-Key", "Coliseu2026!IdentitySuperSecretKeyOauth20")

try:
    with urllib.request.urlopen(req) as response:
        html = response.read().decode('utf-8')
        branches = json.loads(html)
        print(json.dumps(branches, indent=2))
except Exception as e:
    print(f"Error: {e}")
