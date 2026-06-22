import fdb
conn = fdb.connect(dsn=r'C:\Coliseu\Data\PIVETA.FDB', user='SYSDBA', password='masterkey')
c = conn.cursor()

c.execute("SELECT ID_DEPTO, COUNT(*) FROM CONTAS WHERE BAIXA = 0 GROUP BY ID_DEPTO")
for row in c.fetchall():
    print(f"ID_DEPTO (Branch/Depto): {row[0]}, Unpaid Bills Count: {row[1]}")

conn.close()
