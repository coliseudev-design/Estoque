import fdb

conn = fdb.connect(dsn=r'C:\Coliseu\Data\PIVETA.FDB', user='SYSDBA', password='masterkey', charset='WIN1252')
cur = conn.cursor()

cur.execute("SELECT ID_FUNCIONARIO, NOME, MOB_ACESSO, ID_EMPRESA FROM FUNCIONARIOS WHERE ID_FUNCIONARIO = 105")
columns = [desc[0] for desc in cur.description]
for row in cur.fetchall():
    print(dict(zip(columns, row)))

conn.close()
