import fdb

con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey')
cur = con.cursor()
cur.execute("SELECT FIRST 1 * FROM DASH_VENDAS")
print([desc[0] for desc in cur.description])
