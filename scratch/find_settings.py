import os
import json

def find_valid_configs():
    search_dir = r"C:\Sales"
    if not os.path.exists(search_dir):
        print(f"Directory {search_dir} does not exist")
        return

    found = []
    for root, dirs, files in os.walk(search_dir):
        for file in files:
            if file.lower() == "appsettings.json":
                full_path = os.path.join(root, file)
                try:
                    with open(full_path, "r", encoding="utf-8") as f:
                        data = json.load(f)
                    
                    vps_api = data.get("VpsApi", {})
                    api_key = vps_api.get("ApiKey", "")
                    company_id = vps_api.get("CompanyId", "")
                    
                    ident_api = data.get("IdentityApi", {})
                    tenant_id = ident_api.get("TenantId", "")
                    
                    # If any of these are not placeholders, we want to know!
                    is_placeholder = (
                        api_key in ("CONFIGURE_AQUI_VPS", "97d519634898145e8557b494d13c9c9b", "") or
                        tenant_id in ("00000000-0000-0000-0000-000000000000", "CONFIGURE_AQUI_UUID_DA_EMPRESA", "")
                    )
                    
                    if not is_placeholder:
                        found.append({
                            "path": full_path,
                            "ApiKey": api_key,
                            "CompanyId": company_id,
                            "TenantId": tenant_id
                        })
                except Exception as e:
                    pass

    if found:
        print(f"Found {len(found)} valid configs:")
        for idx, item in enumerate(found):
            print(f"\n[{idx+1}] Path: {item['path']}")
            print(f"    ApiKey: {item['ApiKey']}")
            print(f"    CompanyId: {item['CompanyId']}")
            print(f"    TenantId: {item['TenantId']}")
    else:
        print("No valid configs found with custom ApiKey/TenantId.")

if __name__ == "__main__":
    find_valid_configs()
