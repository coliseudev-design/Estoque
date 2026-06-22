import urllib.request
import json

identity_url = "https://adminlicencas.coliseusistemas.com.br"
company_id = "fb30c585-d3db-4f1d-82ce-01264d2f555a" # ECHO SISTEMAS
internal_key = "Coliseu2026!IdentitySuperSecretKeyOauth20"

def get_firebird_config():
    print(f"=== Fetching Firebird config for company {company_id} ===")
    url = f"{identity_url}/internal/companies/{company_id}/firebird-config"
    req = urllib.request.Request(url)
    req.add_header("X-Internal-Api-Key", internal_key)
    try:
        with urllib.request.urlopen(req) as res:
            data = json.loads(res.read().decode('utf-8'))
            print("Firebird Configuration on Identity Server:")
            print(json.dumps(data, indent=2))
            return data
    except Exception as e:
        print(f"Error fetching Firebird config: {e}")
        return None

if __name__ == "__main__":
    get_firebird_config()
