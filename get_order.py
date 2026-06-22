import fdb

con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey')
cur = con.cursor()
cur.execute("SELECT ID_DEPTO, NOTA_FISCAL FROM PEDIDOS WHERE ID_PEDIDO = 529630")
row = cur.fetchone()
print(f"ID_DEPTO: {row[0]}, NOTA_FISCAL: {row[1]}")
