import fdb

con = fdb.connect(dsn=r"C:\Coliseu\Data\PIVETA.FDB", user="SYSDBA", password="masterkey")
cur = con.cursor()

cur.execute("""
    SELECT ID_PEDIDO, PEDIDO, STATUS, DATA_HORA 
    FROM PEDIDOS 
    WHERE ID_MOBILE = 1 AND STATUS = 2
    ORDER BY ID_PEDIDO DESC
""")
orders = cur.fetchall()

missing_estoque = []
for pid, nr, status, dt in orders:
    cur.execute("SELECT COUNT(*) FROM ESTOQUE WHERE ID_PEDIDO = ?", (pid,))
    count = cur.fetchone()[0]
    if count == 0:
        missing_estoque.append((pid, nr, status, dt))

print(f"Found {len(missing_estoque)} faturado mobile orders with 0 ESTOQUE rows:")
for pid, nr, status, dt in missing_estoque:
    print(f"ID_PEDIDO: {pid}, PEDIDO: {nr}, STATUS: {status}, DATA_HORA: {dt}")
