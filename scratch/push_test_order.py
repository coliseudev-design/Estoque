import fdb
import requests
import json
from decimal import Decimal

# Connect to Firebird and get order 529695
con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey')
cur = con.cursor()

# Get order record
cur.execute("SELECT * FROM DASH_VENDAS WHERE id_firebird = 529695")
col_names = [col[0].lower() for col in cur.description]
row = cur.fetchone()
if not row:
    print("Order 529695 not found in Firebird DASH_VENDAS")
    con.close()
    exit()

order_dict = {}
for name, val in zip(col_names, row):
    if isinstance(val, Decimal):
        order_dict[name] = float(val)
    elif hasattr(val, 'isoformat'):
        order_dict[name] = val.isoformat()
    else:
        order_dict[name] = val

print("Order payload to push:")
print(json.dumps(order_dict, indent=2))

# Post to Dashboard API
base_url = "https://dashboard.coliseusistemas.com.br"
headers = {
    "X-Internal-Key": "COL-YUZA-9WSK-TN88",
    "X-Tenant-Id": "1e40d65f-4319-4c68-ae13-66223820c095",
    "Content-Type": "application/json"
}

resp = requests.post(f"{base_url}/internal/sync/dash_vendas", headers=headers, json={"rows": [order_dict]})
print("\nPush Order status:", resp.status_code)
print("Push Order body:", resp.text)

# Also get its items from DASH_VENDAS_ITENS
cur.execute("SELECT * FROM DASH_VENDAS_ITENS WHERE venda_id_firebird = 529695")
item_cols = [col[0].lower() for col in cur.description]
item_rows = cur.fetchall()
items_list = []
for i_row in item_rows:
    item_dict = {}
    for name, val in zip(item_cols, i_row):
        if isinstance(val, Decimal):
            item_dict[name] = float(val)
        elif hasattr(val, 'isoformat'):
            item_dict[name] = val.isoformat()
        else:
            item_dict[name] = val
    items_list.append(item_dict)

print(f"\nItems count for order 529695: {len(items_list)}")
if items_list:
    print("First item payload:")
    print(json.dumps(items_list[0], indent=2))

    resp_items = requests.post(f"{base_url}/internal/sync/dash_vendas_itens", headers=headers, json={"rows": items_list})
    print("\nPush Items status:", resp_items.status_code)
    print("Push Items body:", resp_items.text)

con.close()
