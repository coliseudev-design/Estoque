import fdb

con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey')
cur = con.cursor()
cur.execute("SELECT ID_PEDIDO, DATA_HORA, DATA_VENCIMENTO, STATUS, ID_NATUREZA, ID_DEPTO FROM PEDIDOS WHERE ID_PEDIDO >= 529692")
rows = cur.fetchall()
for row in rows:
    print(f"ID: {row[0]}, DATA_HORA: {row[1]}, DATA_VENCIMENTO: {row[2]}, STATUS: {row[3]}, ID_NATUREZA: {row[4]}, ID_DEPTO: {row[5]}")
con.close()
