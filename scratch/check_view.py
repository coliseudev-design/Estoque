import fdb

con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey')
cur = con.cursor()
cur.execute("SELECT id_firebird, numero_pedido, data_venda, cliente_id_firebird, vendedor_id_firebird, valor_total, status, marca, categoria, especie FROM DASH_VENDAS WHERE id_firebird >= 529692")
rows = cur.fetchall()
print(f"Found {len(rows)} rows in DASH_VENDAS:")
for row in rows:
    print(row)
con.close()
