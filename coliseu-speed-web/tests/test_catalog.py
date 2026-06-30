def test_catalog_query_search_results(client):
    # Query for products using a mock filter
    response = client.get("/api/catalog/query?q=Cabo")
    assert response.status_code == 200
    
    data = response.json()
    assert len(data) >= 1
    assert "Cabo Flexível" in data[0]["name"]
