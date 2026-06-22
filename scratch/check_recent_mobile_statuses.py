import fdb

con = fdb.connect(dsn=r"C:\Coliseu\Data\PIVETA.FDB", user="SYSDBA", password="masterkey")
cur = con.cursor()

cur.execute("SELECT STATUS, COUNT(*) FROM PEDIDOS WHERE ID_MOBILE = 1 GROUP BY STATUS")
rows = cur.fetchall()
print("Mobile orders by STATUS:")
for row in rows:
    print(f"STATUS {row[0]}: {row[1]} orders")
