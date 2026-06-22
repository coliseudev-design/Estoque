import fdb

con = fdb.connect(dsn=r"C:\Coliseu\Data\PIVETA.FDB", user="SYSDBA", password="masterkey")
cur = con.cursor()

cur.execute("SELECT FIRST 10 ID_PEDIDO, ID_MOBILE, PEDIDO, STATUS, DATA_HORA, TIPO FROM PEDIDOS ORDER BY ID_PEDIDO DESC")
cols = [desc[0] for desc in cur.description]
print("Recent orders:")
for row in cur.fetchall():
    print(dict(zip(cols, row)))
