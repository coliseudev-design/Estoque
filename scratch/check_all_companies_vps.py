import urllib.request
import json

api_url = "https://licencas.coliseusistemas.com.br"
api_key = "COL-NZ2Q-U4ZD-CDDH"

companies = {
    "fb30c585-d3db-4f1d-82ce-01264d2f555a": "ECHO SISTEMAS",
    "1e40d65f-4319-4c68-ae13-66223820c095": "Company from test_perf_api.py",
    "a822a7e7-fdd4-4483-bbb5-26587a72739f": "Company from C:\\Sales\\appsettings.json",
    "5805c776-65b6-4df8-bcf5-46e00b68d5ed": "Company from C:\\Coliseu\\Sales\\appsettings.json"
}

endpoints = [
    "company-data",
    "sellers",
    "payment-species",
    "financials",
    "catalog"
]

def check_company(company_id, name):
    print(f"\n===== Checking company: {name} ({company_id}) =====")
    for ep in endpoints:
        headers = {
            "API-Key": api_key,
            "X-Company-Id": company_id,
            "User-Agent": "Mozilla/5.0"
        }
        url = f"{api_url}/api/sync/{ep}"
        req = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(req) as response:
                res = json.loads(response.read().decode('utf-8'))
                synced_at = res.get("syncedAt")
                source = res.get("source")
                
                count = 0
                if "financials" in res:
                    count = len(res["financials"])
                elif "products" in res:
                    count = len(res["products"])
                elif "sellers" in res:
                    count = len(res["sellers"])
                elif "paymentMethods" in res:
                    count = len(res["paymentMethods"])
                elif "data" in res:
                    count = 1 if res["data"] else 0
                
                print(f"  -> /api/sync/{ep}: count={count}, syncedAt={synced_at}, source={source}")
        except Exception as e:
            print(f"  -> /api/sync/{ep}: FAILED ({e})")

if __name__ == "__main__":
    for cid, name in companies.items():
        check_company(cid, name)
