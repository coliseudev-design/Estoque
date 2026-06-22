import fdb
try:
    con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey', charset='WIN1252')
    cur = con.cursor()
    cur.execute("SELECT FIRST 1 DC FROM CONTAS")
    row = cur.fetchone()
    print("DC type:", type(row[0]), "Value:", row[0])
except Exception as e:
    print("ERROR:", e)
