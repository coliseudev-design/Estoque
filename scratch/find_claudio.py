import fdb
conn = fdb.connect(dsn=r'C:\Coliseu\Data\PIVETA.FDB', user='SYSDBA', password='masterkey')
c = conn.cursor()

c.execute("SELECT ID_FUNCIONARIO, NOME, EMAIL, ID_EMPRESA FROM FUNCIONARIOS WHERE NOME LIKE '%CLAUDIO%'")
print("Funcionarios matching 'CLAUDIO':")
for row in c.fetchall():
    print(row)

# Let's count total clients and show vendor IDs present in CLIENTES
c.execute("SELECT ID_VENDEDOR, COUNT(*) FROM CLIENTES GROUP BY ID_VENDEDOR")
print("\nClients group by ID_VENDEDOR:")
for row in c.fetchall():
    print(row)

conn.close()
