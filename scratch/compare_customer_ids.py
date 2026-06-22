import urllib.request
import json

api_url = "https://licencas.coliseusistemas.com.br"
api_key = "COL-RBEH-PKY2-FD8X"
company_id = "fb30c585-d3db-4f1d-82ce-01264d2f555a"
branch_id = "6c8bbc7e-0590-471b-ab50-fd870afbbbec"

def check_data():
    headers = {
        "API-Key": api_key,
        "X-Company-Id": company_id,
        "X-Branch-Id": branch_id,
        "User-Agent": "Mozilla/5.0"
    }

    # Fetch financials
    req_fin = urllib.request.Request(f"{api_url}/api/sync/financials", headers=headers)
    financials = []
    try:
        with urllib.request.urlopen(req_fin) as response:
            res = json.loads(response.read().decode('utf-8'))
            financials = res.get("financials", [])
            print(f"Total financials retrieved: {len(financials)}")
    except Exception as e:
        print(f"Error fetching financials: {e}")

    # Fetch customers
    req_cust = urllib.request.Request(f"{api_url}/api/sync/customers?limit=100", headers=headers)
    customers = []
    try:
        with urllib.request.urlopen(req_cust) as response:
            res = json.loads(response.read().decode('utf-8'))
            customers = res.get("customers", [])
            print(f"Total customers retrieved (sample): {len(customers)}")
    except Exception as e:
        print(f"Error fetching customers: {e}")

    if financials:
        print("\n--- Financials CustomerId Samples ---")
        fin_cust_ids = set()
        for f in financials[:10]:
            c_id = f.get('customerId') or f.get('customerid') or f.get('CUSTOMERID') or f.get('customer_id')
            fin_cust_ids.add(c_id)
            print(f"Doc: {f.get('docNumber')}, CustomerId: {c_id}, Amount: {f.get('amount')}")
        print("All unique CustomerIds in first 10 titles:", fin_cust_ids)

    if customers:
        print("\n--- Customers Id Samples ---")
        cust_ids = set()
        for c in customers[:10]:
            cust_ids.add(c.get('id'))
            print(f"Customer Name: {c.get('name')}, Id: {c.get('id')}")

if __name__ == "__main__":
    check_data()
