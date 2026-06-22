import urllib.request
import json

api_url = "https://licencas.coliseusistemas.com.br"
company_id = "fb30c585-d3db-4f1d-82ce-01264d2f555a" # ECHO SISTEMAS

keys = [
    "COL-NZ2Q-U4ZD-CDDH",
    "2bb4e34436aa52baa1c5937a01a7eb872f4a8046790418294089b23dc6c5928e",
    "97d519634898145e8557b494d13c9c9b"
]

for api_key in keys:
    print(f"\n--- Testing key: {api_key} ---")
    req = urllib.request.Request(
        f"{api_url}/api/sync/financials",
        headers={
            "API-Key": api_key,
            "X-Company-Id": company_id,
            "User-Agent": "Mozilla/5.0"
        }
    )
    try:
        with urllib.request.urlopen(req) as response:
            res = json.loads(response.read().decode('utf-8'))
            financials = res.get("financials", [])
            print("SUCCESS!")
            print("SyncedAt:", res.get("syncedAt"))
            print("Total financial titles in VPS:", len(financials))
            if len(financials) > 0:
                print("First 3 titles sample:")
                for item in financials[:3]:
                    print(f"  - Doc: {item.get('docNumber')}, Amount: {item.get('amount')}, DueDate: {item.get('dueDate')}, Paid: {item.get('isPaid')}")
            break
    except Exception as e:
        print("Failed:", e)
