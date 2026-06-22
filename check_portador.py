import fdb
con = fdb.connect(dsn=r"C:\Coliseu\Data\PIVETA.FDB", user="SYSDBA", password="masterkey")
cur = con.cursor()
cur.execute("SELECT ID_PEDIDO, ID_PORTADOR, ID_DEPTO FROM PEDIDOS ORDER BY ID_PEDIDO DESC ROWS 10")
for row in cur:
    print(row)
