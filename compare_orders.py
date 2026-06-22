import fdb
con = fdb.connect(dsn=r"C:\Coliseu\Data\PIVETA.FDB", user="SYSDBA", password="masterkey")
cur = con.cursor()

# Get columns in correct order
cur.execute("SELECT RDB$FIELD_NAME FROM RDB$RELATION_FIELDS WHERE RDB$RELATION_NAME = 'PEDIDOS' ORDER BY RDB$FIELD_POSITION")
columns = [row[0].strip() for row in cur.fetchall()]

# Get #529622 (old, Depto 1)
cur.execute("SELECT * FROM PEDIDOS WHERE ID_PEDIDO = 529622")
row_old = cur.fetchone()
old_dict = dict(zip(columns, row_old))

# Get #529628 (new, Depto 3)
cur.execute("SELECT * FROM PEDIDOS WHERE ID_PEDIDO = 529628")
row_new = cur.fetchone()
new_dict = dict(zip(columns, row_new))

# Compare
print("DIFFERENCES:")
for col in columns:
    old_val = old_dict.get(col)
    new_val = new_dict.get(col)
    if old_val != new_val:
        print(f"{col}: old={old_val} | new={new_val}")
