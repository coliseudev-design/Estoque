import fdb

con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey')
cur = con.cursor()
cur.execute("SELECT ID_PRODUTO, VALOR_UNITARIO, QTDE, VALOR_TOTAL FROM PEDIDO_ITENS WHERE ID_PEDIDO = 529631")
rows = cur.fetchall()
for r in rows:
    print(f"PROD: {r[0]}, UNIT: {r[1]}, QTDE: {r[2]}, TOTAL: {r[3]}")
