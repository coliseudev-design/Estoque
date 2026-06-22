import fdb

con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey')
cur = con.cursor()
cur.execute("SELECT ID_PEDIDO, ID_DEPTO, NOTA_FISCAL, VALOR_PEDIDO, VALOR_DESCONTO, TOTAL_PEDIDO, ID_CLIENTE FROM PEDIDOS WHERE ID_PEDIDO = 529631")
row = cur.fetchone()
if row:
    print(f"ID: {row[0]}, DEPTO: {row[1]}, NOTA_FISCAL: {row[2]}, VALOR_PEDIDO: {row[3]}, VALOR_DESCONTO: {row[4]}")
else:
    print("Not found")
