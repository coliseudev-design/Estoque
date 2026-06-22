import fdb

con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey')
cur = con.cursor()
cur.execute("""
    SELECT p.ID_PEDIDO, p.STATUS, p.TIPO, p.DATA_VENCIMENTO, p.ID_DEPTO, p.ID_VENDEDOR
    FROM PEDIDOS p
    WHERE p.ID_PEDIDO IN (529699, 529698)
""")
columns = [col[0] for col in cur.description]
rows = cur.fetchall()
for row in rows:
    row_dict = dict(zip(columns, row))
    print(row_dict)
con.close()
