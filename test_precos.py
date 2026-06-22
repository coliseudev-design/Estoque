import fdb
conn = fdb.connect(dsn=r'C:\Coliseu\Data\PIVETA.FDB',user='SYSDBA',password='masterkey')
c = conn.cursor()
c.execute("SELECT FIRST 1 * FROM PRODUTO_PRECOS")
row = c.fetchone()
columns = [desc[0] for desc in c.description]
if row:
    print(dict(zip(columns, row)))
else:
    print(columns)
