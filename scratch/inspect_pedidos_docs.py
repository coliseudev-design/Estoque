import fdb

con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey', charset='WIN1252')
cur = con.cursor()

pids = [529699, 529674]
for pid in pids:
    print(f"\n=== PEDIDOS_DOCS for Pedido {pid} ===")
    cur.execute("SELECT * FROM PEDIDOS_DOCS WHERE ID_PEDIDO = ?", (pid,))
    cols = [desc[0] for desc in cur.description]
    rows = cur.fetchall()
    if rows:
        print(" | ".join(cols))
        print("-" * 100)
        for row in rows:
            print(" | ".join(str(val) for val in row))
    else:
        print("No documents found.")

con.close()
