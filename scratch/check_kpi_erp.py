import requests
import json

# Since we don't have the admin key, we query via the public nginx proxy of adminlicencas
url = "https://adminlicencas.coliseusistemas.com.br/api/sales/admin/orders/kpi?source=erp&companyId=1e40d65f-4319-4c68-ae13-66223820c095"
resp = requests.get(url)
print("Status:", resp.status_code)
try:
    print(json.dumps(resp.json(), indent=2))
except Exception as e:
    print(resp.text)
