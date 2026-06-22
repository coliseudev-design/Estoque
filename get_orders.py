import fdb

con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey')
cur = con.cursor()
cur.execute("SELECT ID_PEDIDO, ID_DEPTO, VALOR_PEDIDO, VALOR_CUSTOS, ID_VENDEDOR, DATA_HORA FROM PEDIDOS WHERE ID_PEDIDO IN (529630, 529631)")
rows = cur.fetchall()
for r in rows:
    print(f"ID: {r[0]}, DEPTO: {r[1]}, V_PED: {r[2]}, V_CUS: {r[3]}, VEND: {r[4]}, DATA: {r[5]}")
