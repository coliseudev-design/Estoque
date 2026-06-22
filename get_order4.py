import fdb

con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey')
cur = con.cursor()
cur.execute("SELECT ID_PEDIDO, ID_DEPTO, VALOR_PEDIDO, VALOR_CUSTOS, VALOR_BASE, ITENS, QTDE_TOTAL, DATA_HORA FROM PEDIDOS WHERE ID_PEDIDO = 529631")
row = cur.fetchone()
if row:
    print(f"ID: {row[0]}, DEPTO: {row[1]}, VALOR_PEDIDO: {row[2]}, VALOR_CUSTOS: {row[3]}, VALOR_BASE: {row[4]}, ITENS: {row[5]}, QTDE: {row[6]}, DATA: {row[7]}")
else:
    print("Not found")
