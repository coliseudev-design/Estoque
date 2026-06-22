import fdb

con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey')
cur = con.cursor()
cur.execute("SELECT ID_PEDIDO, STATUS, MOVC, VALOR_TOTAL, VALOR_COMISSAO, ES, TIPO FROM ESTOQUE WHERE ID_PEDIDO IN (529699, 529698)")
columns = [col[0] for col in cur.description]
rows = cur.fetchall()
for row in rows:
    row_dict = dict(zip(columns, row))
    print(row_dict)
con.close()
