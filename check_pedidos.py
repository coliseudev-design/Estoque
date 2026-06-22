import fdb

con = fdb.connect(dsn=r"C:\Coliseu\Data\PIVETA.FDB", user="SYSDBA", password="masterkey")
cur = con.cursor()

cur.execute("SELECT RDB$FIELD_NAME FROM RDB$RELATION_FIELDS WHERE RDB$RELATION_NAME = 'PEDIDOS'")
for row in cur:
    print(row[0].strip())
