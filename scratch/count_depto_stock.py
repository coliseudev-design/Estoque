import fdb
conn = fdb.connect(dsn=r'C:\Coliseu\Data\PIVETA.FDB', user='SYSDBA', password='masterkey')
c = conn.cursor()

c.execute("SELECT ID_DEPTO, COUNT(*), SUM(CASE WHEN ESTOQUE > 0 THEN 1 ELSE 0 END) FROM PRODUTO_DEPTOS GROUP BY ID_DEPTO")
for row in c.fetchall():
    print(f"ID_DEPTO: {row[0]}, Total Products: {row[1]}, Products with Positive Stock: {row[2]}")

conn.close()
