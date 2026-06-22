import fdb
con = fdb.connect(dsn=r"C:\Coliseu\Data\PIVETA.FDB", user="SYSDBA", password="masterkey")
cur = con.cursor()
try:
    sql = """
    UPDATE PEDIDOS P
    SET 
        ITENS = (SELECT COUNT(ID_ITEM) FROM PEDIDO_ITENS PI WHERE PI.ID_PEDIDO = P.ID_PEDIDO),
        QTDE_TOTAL = COALESCE((SELECT SUM(QTDE) FROM PEDIDO_ITENS PI WHERE PI.ID_PEDIDO = P.ID_PEDIDO), 0),
        VALOR_CUSTOS = COALESCE((SELECT SUM(VALOR_CUSTO * QTDE) FROM PEDIDO_ITENS PI WHERE PI.ID_PEDIDO = P.ID_PEDIDO), 0)
    WHERE P.PEDIDO LIKE 'MOB%' AND P.ID_PEDIDO >= 529623
    """
    cur.execute(sql)
    con.commit()
    print("Updated ITENS, QTDE_TOTAL and VALOR_CUSTOS successfully")
except Exception as e:
    print(f"Error: {e}")
