import fdb
try:
    con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey', charset='WIN1252')
    cur = con.cursor()
    cur.execute("SELECT DISTINCT DC FROM CONTAS")
    rows = cur.fetchall()
    print("DC Values:", rows)
except Exception as e:
    print("ERROR:", e)
