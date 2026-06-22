import fdb
conn = fdb.connect(dsn=r'C:\Coliseu\Data\PIVETA.FDB',user='SYSDBA',password='masterkey')
c = conn.cursor()
c.execute("SELECT RDB$RELATION_NAME FROM RDB$RELATIONS WHERE RDB$VIEW_BLR IS NULL AND RDB$SYSTEM_FLAG = 0")
tables = [row[0].strip() for row in c.fetchall() if 'PRECO' in row[0].upper()]
print(tables)
