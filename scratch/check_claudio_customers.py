import fdb
conn = fdb.connect(dsn=r'C:\Coliseu\Data\PIVETA.FDB', user='SYSDBA', password='masterkey')
c = conn.cursor()

c.execute("SELECT COUNT(*) FROM CLIENTES WHERE ID_VENDEDOR = 107")
count = c.fetchone()[0]
print(f"Number of clients with seller ID 107 in CLIENTES: {count}")

c.execute("SELECT FIRST 10 ID_CLIENTE, NOME, ID_VENDEDOR FROM CLIENTES WHERE ID_VENDEDOR = 107")
for row in c.fetchall():
    print(row)

conn.close()
