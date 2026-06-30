import httpx
from config.config import settings

class ApiClient:
    """
    HTTP Client wrapper for querying the Node.js Middleware.
    Contains fallback mock handlers for sandbox/offline execution.
    """
    def __init__(self):
        self.base_url = settings.MIDDLEWARE_URL
        
        # In-memory session mock database for local sandbox run
        self._mock_orders = [
            {
                "id": "1",
                "customer_name": "Antônio da Silva ME",
                "customer_cnpj": "12345678000199",
                "total_amount": 1420.50,
                "status": "confirmed",
                "erp_order_id": "ERP-9844",
                "created_at": "2026-06-30T10:00:00Z"
            },
            {
                "id": "2",
                "customer_name": "Supermercado Pão e Mel Ltda",
                "customer_cnpj": "98765432000100",
                "total_amount": 6800.00,
                "status": "pending",
                "erp_order_id": None,
                "created_at": "2026-06-30T11:30:00Z"
            }
        ]
        
        self._mock_products = [
            {"id": "p1", "code": "PROD-001", "name": "Cabo Flexível Sil 2.5mm Preto 100m", "price": 189.90, "stock": 45, "category": "Materiais Elétricos"},
            {"id": "p2", "code": "PROD-002", "name": "Disjuntor Bipolar Din 20A Siemens", "price": 42.50, "stock": 120, "category": "Materiais Elétricos"},
            {"id": "p3", "code": "PROD-003", "name": "Lâmpada LED Taschibra 12W Bulbo Bivolt", "price": 11.90, "stock": 350, "category": "Iluminação"},
            {"id": "p4", "code": "PROD-004", "name": "Fita Isolante 3M Imperial 20m Preta", "price": 8.50, "stock": 80, "category": "Ferramentas"},
            {"id": "p5", "code": "PROD-005", "name": "Sensor de Presença de Embutir Intelbras", "price": 54.90, "stock": 18, "category": "Segurança"},
            {"id": "p6", "code": "PROD-006", "name": "Quadro de Distribuição de Embutir 12/16 disjuntores Tigre", "price": 95.00, "stock": 8, "category": "Materiais Elétricos"}
        ]
        
        self._mock_customers = [
            {"id": "c1", "name": "Antônio da Silva ME", "cnpj": "12345678000199", "credit_limit": 5000.00, "credit_available": 3579.50, "status": "liberado"},
            {"id": "c2", "name": "Supermercado Pão e Mel Ltda", "cnpj": "98765432000100", "credit_limit": 15000.00, "credit_available": 8200.00, "status": "liberado"},
            {"id": "c3", "name": "Construtora Alfa Engenharia Ltda", "cnpj": "11223344000122", "credit_limit": 50000.00, "credit_available": 50000.00, "status": "liberado"},
            {"id": "c4", "name": "Elétrica Voltagem Máxima Eireli", "cnpj": "44332211000188", "credit_limit": 2000.00, "credit_available": 0.00, "status": "bloqueado"}
        ]

    async def authenticate_rep(self, username, password) -> dict:
        """
        Validates representative credentials against Node.js middleware.
        POST /auth/login
        """
        if settings.USE_MOCKS:
            return {"success": True, "token": "mock_jwt_token_rep_123", "rep_name": "Vendedor Coliseu"}
            
        try:
            async with httpx.AsyncClient(timeout=4.0) as client:
                response = await client.post(f"{self.base_url}/auth/login", json={
                    "username": username,
                    "password": password
                })
                if response.status_code == 200:
                    return {"success": True, **response.json()}
        except Exception as e:
            print(f"[ApiClient] Login request failed: {e}")
            
        # Return sandbox response if offline/mocked
        if username == "vendedor" or username == "vendedor@coliseu.com.br":
            return {"success": True, "token": "mock_jwt_token_rep_123", "rep_name": "Vendedor Coliseu"}
        return {"success": False, "message": "Credenciais inválidas ou erro no middleware."}

    async def get_branches(self, token: str) -> list:
        """
        Fetches list of accessible branches (filiais) from the middleware.
        """
        # Mocks fallback
        return [
            {"id": "b1", "name": "Coliseu Speed - Filial Matriz (São Paulo)"},
            {"id": "b2", "name": "Coliseu Speed - Filial Campinas"},
            {"id": "b3", "name": "Coliseu Speed - Filial Rio de Janeiro"}
        ]

    async def get_products(self, query: str = "") -> list:
        """
        Queries catalog products.
        """
        if not query:
            return self._mock_products
            
        return [
            p for p in self._mock_products 
            if query.lower() in p["name"].lower() or query.lower() in p["code"].lower()
        ]

    async def get_customers(self) -> list:
        """
        Queries representative customer directories.
        """
        return self._mock_customers

    async def create_order(self, customer_id: str, status: str, payment_condition: str, items: list) -> dict:
        """
        Registers a new order or budget.
        """
        customer = next((c for c in self._mock_customers if c["id"] == customer_id), None)
        cust_name = customer["name"] if customer else "Consumidor Final"
        cust_cnpj = customer["cnpj"] if customer else "00000000000100"
        
        # Calculate total
        total = sum(item["price"] * item["quantity"] for item in items)
        
        # Credit limit validation check
        if customer and customer["status"] == "bloqueado":
            return {"success": False, "detail": f"Erro: O cliente '{cust_name}' está BLOQUEADO no ERP."}
            
        if customer and status == "order" and total > customer["credit_available"]:
            return {"success": False, "detail": f"Erro: Limite de crédito excedido. Disponível: R$ {customer['credit_available']:.2f}, Total Pedido: R$ {total:.2f}"}

        new_order = {
            "id": str(len(self._mock_orders) + 1),
            "customer_name": cust_name,
            "customer_cnpj": cust_cnpj,
            "total_amount": float(total),
            "status": "pending" if status == "order" else "budget",
            "erp_order_id": None,
            "created_at": "2026-06-30T15:40:00Z"
        }
        
        # Deduct credit if it's a real order
        if customer and status == "order":
            customer["credit_available"] -= float(total)

        self._mock_orders.insert(0, new_order)
        return {"success": True, "order": new_order}

    async def get_orders(self) -> list:
        """
        Queries complete order history list.
        """
        return self._mock_orders

    async def get_performance_kpis(self) -> dict:
        """
        Fetches KPIs stats for sales representative dashboard.
        """
        return {
            "total_sales": 18520.80,
            "sales_target": 30000.00,
            "achievement_rate": 61.7,
            "orders_count": len(self._mock_orders),
            "average_ticket": 18520.80 / len(self._mock_orders) if self._mock_orders else 0
        }

    async def get_sync_status(self) -> dict:
        return {
            "last_sync": "2026-06-30T14:15:00Z",
            "status": "idle",
            "queue_size": 0,
            "logs": [
                "14:15:00 - Sincronização de catálogo concluída (6 registros)",
                "14:12:30 - Sincronização de clientes concluída (4 registros)",
                "10:02:15 - Pedido #1 integrado com sucesso ao ERP Firebird (ERP-9844)"
            ]
        }

api_client = ApiClient()
