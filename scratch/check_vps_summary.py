import urllib.request
import json

api_url = "https://licencas.coliseusistemas.com.br"
api_key = "COL-NZ2Q-U4ZD-CDDH"

req = urllib.request.Request(
    f"{api_url}/api/monitoring/summary",
    headers={
        "API-Key": api_key,
        "User-Agent": "Mozilla/5.0"
    }
)
try:
    with urllib.request.urlopen(req) as response:
        res = json.loads(response.read().decode('utf-8'))
        print("GLOBAL SUMMARY:")
        print(json.dumps(res, indent=2))
except Exception as e:
    print("Error calling global summary:", e)
