import urllib.request
import json

api_url = "https://licencas.coliseusistemas.com.br"
api_key = "COL-NZ2Q-U4ZD-CDDH"

companies = {
    "fb30c585-d3db-4f1d-82ce-01264d2f555a": "ECHO SISTEMAS (Screenshot)",
    "1e40d65f-4319-4c68-ae13-66223820c095": "Company from test_perf_api.py",
    "a822a7e7-fdd4-4483-bbb5-26587a72739f": "Company from local appsettings.json",
    "5805c776-65b6-4df8-bcf5-46e00b68d5ed": "Company from C:\\Coliseu\\Sales\\appsettings.json"
}

for company_id, desc in companies.items():
    print(f"\n--- Checking {desc} ({company_id}) ---")
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
            print(f"SUCCESS! SyncedAt: {res.get('syncedAt')}")
            print(f"Total financial titles in VPS: {len(financials)}")
            if len(financials) > 0:
                print("First 3 titles sample:")
                for item in financials[:3]:
                    print(f"  - Doc: {item.get('docNumber')}, Amount: {item.get('amount')}, DueDate: {item.get('dueDate')}, Paid: {item.get('isPaid')}")
    except Exception as e:
        print("Failed:", e)
