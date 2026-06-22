import fdb
conn = fdb.connect(dsn=r'C:\Coliseu\Data\PIVETA.FDB', user='SYSDBA', password='masterkey')
c = conn.cursor()

c.execute("SELECT RDB$FIELD_NAME FROM RDB$RELATION_FIELDS WHERE RDB$RELATION_NAME = 'CONTAS'")
cols = [r[0].strip() for r in c.fetchall()]
print("CONTAS COLUMNS:")
print(", ".join(cols))

conn.close()
