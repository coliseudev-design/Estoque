import fdb
con = fdb.connect(dsn=r"C:\Coliseu\Data\PIVETA.FDB", user="SYSDBA", password="masterkey")
cur = con.cursor()
cur.execute("SELECT ID_PEDIDO, ID_PRODUTO, QTDE, VALOR_UNITARIO FROM PEDIDO_ITENS WHERE ID_PEDIDO = 529628")
for row in cur:
    print(row)
