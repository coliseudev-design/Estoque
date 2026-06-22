import fdb

con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey')
cur = con.cursor()
cur.execute("""
    SELECT p.ID_PEDIDO, p.STATUS, p.TIPO, p.DATA_VENCIMENTO, p.ID_DEPTO, p.ID_VENDEDOR,
           (SELECT SUM(e.VALOR_TOTAL) FROM ESTOQUE e WHERE e.ID_PEDIDO = p.ID_PEDIDO AND e.STATUS <> 9 AND e.MOVC = 1) as TOTAL_ESTOQUE
    FROM PEDIDOS p
    WHERE p.ID_VENDEDOR = 105 AND p.DATA_VENCIMENTO = '2026-05-20' AND p.TIPO = 1
""")
columns = [col[0] for col in cur.description]
rows = cur.fetchall()
for row in rows:
    row_dict = dict(zip(columns, row))
    print(row_dict)
con.close()
