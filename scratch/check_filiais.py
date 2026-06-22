import fdb

con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey')
cur = con.cursor()
cur.execute("SELECT * FROM DASH_FILIAIS")
cols = [desc[0] for desc in cur.description]
rows = cur.fetchall()
print(f"Columns: {cols}")
for row in rows:
    print(dict(zip(cols, row)))
con.close()
