import fdb

con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey')
cur = con.cursor()
cur.execute("""
    SELECT e.ID_PEDIDO, e.ES, e.TIPO, e.VALOR_TOTAL, e.STATUS, e.MOVC
    FROM ESTOQUE e
    WHERE e.ID_PEDIDO IN (529699, 529698)
""")
columns = [col[0] for col in cur.description]
rows = cur.fetchall()
for row in rows:
    row_dict = dict(zip(columns, row))
    print(row_dict)
con.close()
