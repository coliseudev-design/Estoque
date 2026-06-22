import fdb
con = fdb.connect(dsn=r"C:\Coliseu\Data\PIVETA.FDB", user="SYSDBA", password="masterkey")
cur = con.cursor()
cur.execute("SELECT ID_PEDIDO, PEDIDO, ID_CLIENTE, ID_DEPTO, STATUS, TIPO, DATA_HORA FROM PEDIDOS ORDER BY ID_PEDIDO DESC ROWS 5")
for row in cur:
    print(row)
