import urllib.request
import urllib.error
import json

URL = "https://licencas.coliseusistemas.com.br/api/orders/report?limit=100"
API_KEY = "97d519634898145e8557b494d13c9c9b"

req = urllib.request.Request(
    URL,
    headers={
        "API-Key": API_KEY,
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
    },
    method="GET"
)

try:
    with urllib.request.urlopen(req) as response:
        res_data = response.read().decode('utf-8')
        data = json.loads(res_data)
        
        with open("c:/Users/rober/.gemini/antigravity/scratch/Coliseu_Sales/scratch/orders_report_prod.json", "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            
        print("Success! Report written to orders_report_prod.json")
        print("Total orders found:", len(data.get("orders", [])))
        for order in data.get("orders", []):
            if order.get("sync_status") == "error":
                print(f"Error Order - ID: {order.get('id')}, Client: {order.get('client_name')}, Total: {order.get('total_amount')}, Status: {order.get('sync_status')}, Msg: {order.get('error_message')}")
except urllib.error.HTTPError as e:
    print(f"HTTP Error {e.code}!")
    print(e.read().decode('utf-8'))
except Exception as e:
    print("Error:", str(e))
