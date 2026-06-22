import fdb

con = fdb.connect(dsn=r"C:\Coliseu\Data\PIVETA.FDB", user="SYSDBA", password="masterkey")
cur = con.cursor()

cur.execute("SELECT FIRST 10 ID_PEDIDO, PEDIDO, STATUS, DATA_HORA FROM PEDIDOS WHERE ID_MOBILE = 1 ORDER BY ID_PEDIDO DESC")
orders = cur.fetchall()

print(f"{'PEDIDO_ID':<12} | {'PEDIDO_NR':<10} | {'STATUS':<6} | {'ESTOQUE_ROWS':<12}")
print("-" * 50)
for pid, nr, status, dt in orders:
    cur.execute("SELECT COUNT(*) FROM ESTOQUE WHERE ID_PEDIDO = ?", (pid,))
    count = cur.fetchone()[0]
    print(f"{pid:<12} | {nr:<10} | {status:<6} | {count:<12}")
