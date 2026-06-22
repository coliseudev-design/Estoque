"""
Verifica os KPIs de todos os vendedores para cada filial.
Mostra o que o middleware retorna quando se usa o JWT de cada filial.
"""
import urllib.request
import urllib.parse
import json

BASE_URL = "https://licencas.coliseusistemas.com.br"

BRANCHES = [
    {"name": "PIVETA DIST", "id": "a5ade2d9-a169-40f5-922a-704262867dff", "depto": 1},
    {"name": "LOJA 2",      "id": "bd545509-e046-42d3-9883-d3ba9e2c8cf7", "depto": 2},
    {"name": "LOJA 3",      "id": "7508465a-4c84-4a1f-83e2-4a9313f805d9", "depto": 3},
]

SELLER_IDS = [105, 106, 107, 108]

INTERNAL_KEY = "Coliseu2026!IdentitySuperSecretKeyOauth20"

def get_jwt_for_branch(branch_id):
    """Gera um token de device para a filial especificada."""
    url = f"https://adminlicencas.coliseusistemas.com.br/internal/auth/device-token"
    data = json.dumps({
        "branchId": branch_id,
        "deviceId": "test-device-check",
        "deviceName": "Diagnostico"
    }).encode()
    req = urllib.request.Request(url, data=data, method="POST")
    req.add_header("Content-Type", "application/json")
    req.add_header("X-Internal-Api-Key", INTERNAL_KEY)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            body = json.loads(resp.read())
            return body.get("accessToken") or body.get("token")
    except Exception as e:
        print(f"  Erro ao gerar JWT para branch {branch_id}: {e}")
        return None

print("=== Diagnóstico KPIs por Filial e Vendedor ===\n")
import datetime
now = datetime.datetime.now()
month = now.month
year  = now.year

for branch in BRANCHES:
    print(f"\n--- Filial: {branch['name']} (deptoId={branch['depto']}) ---")
    token = get_jwt_for_branch(branch["id"])
    if not token:
        print("  [ERRO] Não foi possível gerar JWT")
        continue

    for seller_id in SELLER_IDS:
        params = urllib.parse.urlencode({
            "sellerId": seller_id,
            "month": month,
            "year": year
        })
        url = f"{BASE_URL}/api/sync/performance?{params}"
        req = urllib.request.Request(url)
        req.add_header("Authorization", f"Bearer {token}")
        req.add_header("X-Branch-Id", branch["id"])
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                body = json.loads(resp.read())
                data = body.get("data")
                source = body.get("source", "?")
                if data:
                    venda = data.get("vendaMensal", 0)
                    depto_returned = data.get("deptoId", "?")
                    print(f"  Seller {seller_id}: vendaMensal=R${venda:.2f}  deptoId={depto_returned}  source={source}")
                else:
                    print(f"  Seller {seller_id}: [SEM DADOS]  source={source}")
        except Exception as e:
            print(f"  Seller {seller_id}: [ERRO] {e}")
