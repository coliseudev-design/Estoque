import fdb

con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey')
cur = con.cursor()
cur.execute("SELECT ID_PEDIDO, VALOR_PEDIDO, ID_NATUREZA FROM PEDIDOS WHERE ID_PEDIDO IN (529630, 529631)")
rows = cur.fetchall()
for r in rows:
    print(f"ID: {r[0]}, V_PED: {r[1]}, NAT: {r[2]}")
