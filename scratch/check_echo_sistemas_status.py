import urllib.request
import json

identity_url = "https://adminlicencas.coliseusistemas.com.br"
api_url = "https://licencas.coliseusistemas.com.br"

company_id = "fb30c585-d3db-4f1d-82ce-01264d2f555a" # ECHO SISTEMAS
api_key = "COL-RBEH-PKY2-FD8X"
internal_key = "Coliseu2026!IdentitySuperSecretKeyOauth20"

def get_branches():
    print(f"=== Fetching branches for company {company_id} from Identity ===")
    url = f"{identity_url}/internal/companies/{company_id}/branches"
    req = urllib.request.Request(url)
    req.add_header("X-Internal-Api-Key", internal_key)
    try:
        with urllib.request.urlopen(req) as res:
            data = json.loads(res.read().decode('utf-8'))
            print("Branches found:")
            print(json.dumps(data, indent=2))
            return data
    except Exception as e:
        print(f"Error fetching branches: {e}")
        return []

def get_company_details():
    print(f"=== Fetching company details from Identity ===")
    url = f"{identity_url}/internal/companies/{company_id}"
    req = urllib.request.Request(url)
    req.add_header("X-Internal-Api-Key", internal_key)
    try:
        with urllib.request.urlopen(req) as res:
            data = json.loads(res.read().decode('utf-8'))
            print("Company details:")
            print(json.dumps(data, indent=2))
            return data
    except Exception as e:
        print(f"Error fetching company details: {e}")
        return None

def check_sync_endpoint(endpoint, branch_id=None):
    desc = f"{endpoint}"
    if branch_id:
        desc += f" (Branch: {branch_id})"
    
    headers = {
        "API-Key": api_key,
        "X-Company-Id": company_id,
        "User-Agent": "Mozilla/5.0"
    }
    if branch_id:
        headers["X-Branch-Id"] = branch_id

    url = f"{api_url}/api/sync/{endpoint}"
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req) as response:
            res = json.loads(response.read().decode('utf-8'))
            synced_at = res.get("syncedAt")
            source = res.get("source")
            
            # Count elements based on response keys
            count = 0
            if "financials" in res:
                count = len(res["financials"])
            elif "products" in res:
                count = len(res["products"])
            elif "sellers" in res:
                count = len(res["sellers"])
            elif "paymentMethods" in res:
                count = len(res["paymentMethods"])
            elif "paymentConditions" in res:
                count = len(res["paymentConditions"])
            elif "data" in res:
                count = 1 if res["data"] else 0
            
            print(f"  -> /api/sync/{endpoint}: SUCCESS! count={count}, syncedAt={synced_at}, source={source}")
            return res
    except Exception as e:
        print(f"  -> /api/sync/{endpoint}: FAILED ({e})")
        return None

if __name__ == "__main__":
    company_details = get_company_details()
    branches = get_branches()
    
    print("\n=== Checking Sync Endpoints on VPS ===")
    # List of endpoints to query
    endpoints = [
        "company-data",
        "sellers",
        "payment-species",
        "financials",
        "catalog",
        "payment-conditions",
        "price-tables",
        "product-prices"
    ]
    
    for ep in endpoints:
        check_sync_endpoint(ep)
        
    if branches and isinstance(branches, list):
        print("\n=== Checking Sync Endpoints with Branch Headers ===")
        for branch in branches:
            b_id = branch.get("id")
            b_name = branch.get("name") or branch.get("id_filial")
            print(f"\nChecking for Branch: {b_name} ({b_id})")
            for ep in ["financials", "catalog", "sellers"]:
                check_sync_endpoint(ep, branch_id=b_id)
