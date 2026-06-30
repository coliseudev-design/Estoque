def test_order_creation_credit_limit_validation(client):
    # Test order with client that exceeds credit limit
    payload = {
        "customer_id": "c4", # Elétrica Voltagem (credit limit 0, blocked)
        "status": "order",
        "payment_condition": "dinheiro",
        "items": [
            {"product_id": "p1", "quantity": 10, "price": 189.90}
        ]
    }
    
    response = client.post("/api/orders/new", json=payload)
    assert response.status_code == 400
    assert "BLOQUEADO" in response.json()["detail"]
