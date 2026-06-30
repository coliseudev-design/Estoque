from typing import Dict, Any

def generate_order_invoice_text(order: Dict[str, Any]) -> str:
    """
    Generates a cleanly formatted text/HTML string representing an invoice/receipt
    for downloading or sharing with the customer.
    """
    total = order.get("total_amount", 0.0)
    erp_id = order.get("erp_order_id") or "Aguardando Integração"
    
    html = f"""
==================================================
              COLISEU SPEED - PEDIDO
==================================================
Número do Pedido: {order.get("id")}
ERP Código Ref:   {erp_id}
Data Emissão:     {order.get("created_at")}
Status do Pedido: {order.get("status").upper()}
--------------------------------------------------
CLIENTE
Nome / Razão:     {order.get("customer_name")}
Documento (CNPJ): {order.get("customer_cnpj")}
--------------------------------------------------
DADOS FINANCEIROS
Valor Total:      R$ {total:.2f}
Condição Pgto:    30 Dias Boleto (Padrão)
--------------------------------------------------
Agradecemos a preferência!
Gerado eletronicamente por ColiseuSpeed Force.
==================================================
"""
    return html.strip()
