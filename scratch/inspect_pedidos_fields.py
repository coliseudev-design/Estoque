import fdb

con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey', charset='WIN1252')
cur = con.cursor()

print("--- Synced mobile orders (TIPO_DAV and CONTROLE_FP values) ---")
cur.execute("SELECT FIRST 10 ID_PEDIDO, TIPO_DAV, CONTROLE_FP FROM PEDIDOS WHERE ID_MOBILE = 1 ORDER BY ID_PEDIDO DESC")
for row in cur.fetchall():
    print(f"ID: {row[0]}, TIPO_DAV: {row[1]}, CONTROLE_FP: {row[2]}")

print("\n--- Native ERP orders (TIPO_DAV and CONTROLE_FP values) ---")
cur.execute("SELECT FIRST 10 ID_PEDIDO, TIPO_DAV, CONTROLE_FP FROM PEDIDOS WHERE ID_MOBILE IS NULL AND TIPO = 1 ORDER BY ID_PEDIDO DESC")
for row in cur.fetchall():
    print(f"ID: {row[0]}, TIPO_DAV: {row[1]}, CONTROLE_FP: {row[2]}")

con.close()
