import urllib.request
import urllib.parse
import json

url = "https://licencas.coliseusistemas.com.br/api/sync/performance"
branches = {
    "PIVETA DIST": "a5ade2d9-a169-40f5-922a-704262867dff",
    "LOJA 2": "bd545509-e046-42d3-9883-d3ba9e2c8cf7",
    "LOJA 3": "7508465a-4c84-4a1f-83e2-4a9313f805d9"
}

for name, bid in branches.items():
    headers = {
        "api-key": "COL-NZ2Q-U4ZD-CDDH",
        "X-Branch-Id": bid,
        "Content-Type": "application/json"
    }
    params = {
        "sellerId": "105",
        "month": 5,
        "year": 2026
    }
    query_string = urllib.parse.urlencode(params)
    full_url = f"{url}?{query_string}"
    print(f"\n--- Querying {name} ({bid}) ---")
    req = urllib.request.Request(full_url, headers=headers)
    try:
        with urllib.request.urlopen(req) as response:
            status_code = response.getcode()
            body = response.read().decode('utf-8')
            print(f"Status Code: {status_code}")
            res_json = json.loads(body)
            print(json.dumps(res_json, indent=2))
    except Exception as e:
        print(f"Error: {e}")

