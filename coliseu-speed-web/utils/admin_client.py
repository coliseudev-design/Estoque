import httpx
from config.config import settings

class AdminClient:
    """
    Client for querying the ColiseuSpeed SaaS Admin Panel API.
    Used for license status checks and active API integrations retrieval.
    """
    def __init__(self):
        self.base_url = settings.ADMIN_PANEL_URL

    async def get_license_status(self, company_id: str = None) -> dict:
        """
        Validates if the client tenant has an active license in the Admin Panel.
        Path: GET /adm/api/companies/{company_id}/licenses/validate
        """
        if settings.USE_MOCKS:
            return {
                "valid": True,
                "product_type": "coliseu_speed",
                "status": "active",
                "max_users": 10,
                "features": ["catalog", "orders", "offline_sync"]
            }

        cid = company_id or settings.COMPANY_ID
        try:
            async with httpx.AsyncClient(timeout=4.0) as client:
                url = f"{self.base_url}/adm/api/companies/{cid}/licenses/1/validate"
                response = await client.get(url)
                if response.status_code == 200:
                    return response.json()
        except Exception as e:
            print(f"[AdminClient] Failed to reach SaaS Admin Panel for {cid}: {e}. Falling back to default mock license.")
            
        # Return fallback active mock if offline
        return {
            "valid": True,
            "product_type": "coliseu_speed",
            "status": "active",
            "max_users": 5,
            "features": ["catalog", "orders", "offline_sync"]
        }

    async def get_active_integrations(self, company_id: str = None) -> dict:
        """
        Returns active third-party APIs (WhatsApp, Fiscal, Contract) configured for this company.
        """
        mock_integrations = {
            "whatsapp": {"enabled": True, "configuration": {"phone": "5511999998888"}},
            "email": {"enabled": True, "configuration": {"sender": "vendas@coliseusistemas.com.br"}},
            "fiscal": {"enabled": False},
            "contract": {"enabled": True}
        }
        
        if settings.USE_MOCKS:
            return mock_integrations

        cid = company_id or settings.COMPANY_ID
        try:
            async with httpx.AsyncClient(timeout=4.0) as client:
                url = f"{self.base_url}/adm/api/companies/{cid}/integrations"
                response = await client.get(url)
                if response.status_code == 200:
                    data = response.json()
                    integrations = {
                        "whatsapp": {"enabled": False},
                        "email": {"enabled": True}, # default email always enabled
                        "fiscal": {"enabled": False},
                        "contract": {"enabled": False}
                    }
                    for item in data:
                        api_type = item.get("api_type")
                        if api_type in integrations:
                            integrations[api_type] = {
                                "enabled": item.get("is_active", False),
                                "configuration": item.get("configuration", {})
                            }
                    return integrations
        except Exception as e:
            print(f"[AdminClient] Failed to retrieve integrations from Admin for {cid}: {e}")
            
        return mock_integrations

admin_client = AdminClient()
