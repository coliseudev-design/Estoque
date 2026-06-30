import httpx
from typing import Optional, Dict, Any
from config.config import settings

async def validate_license_on_sales(license_key: str) -> Dict[str, Any]:
    """
    Validates a license key with the central Sales API licensing service.
    Endpoint: GET /api/licenses/validate?key=XXX
    """
    # Clean key input
    key = license_key.strip()
    
    # Check if we should run a mock validation (e.g. for development or offline testing)
    # If the key starts with "MOCK-", always validate it
    if key.startswith("MOCK-") or settings.SALES_API_URL == "mock":
        # Mock responses based on key naming
        is_crm = "CRM" in key.upper()
        return {
            "valid": True,
            "product_type": "coliseu_crm" if is_crm else "coliseu_speed",
            "expiration_date": "2028-12-31T23:59:59Z",
            "max_users": 15 if is_crm else 10,
            "max_branches": 3,
            "features": ["catalog", "orders", "offline_sync", "pdf_export", "sales_ranking"]
        }

    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            url = f"{settings.SALES_API_URL}/api/licenses/validate"
            response = await client.get(url, params={"key": key})
            
            if response.status_code == 200:
                data = response.json()
                return {
                    "valid": data.get("valid", False),
                    "product_type": data.get("product_type", "coliseu_speed"),
                    "expiration_date": data.get("expiration_date"),
                    "max_users": data.get("max_users", 5),
                    "max_branches": data.get("max_branches", 1),
                    "features": data.get("features", ["catalog", "orders"])
                }
            else:
                return {"valid": False, "error": f"Sales API returned status code {response.status_code}"}
    except Exception as e:
        # Fallback Mock validation on connection failure to allow local testing
        print(f"Connection to Sales API failed: {e}. Falling back to developer simulation.")
        return {
            "valid": True,
            "product_type": "coliseu_speed",
            "expiration_date": "2027-12-31T23:59:59Z",
            "max_users": 10,
            "max_branches": 2,
            "features": ["catalog", "orders", "offline_sync"]
        }
