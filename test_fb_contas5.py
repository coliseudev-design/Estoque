import fdb
try:
    con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey', charset='WIN1252')
    cur = con.cursor()
    cur.execute("SELECT RDB$FIELD_NAME, RDB$FIELD_SOURCE FROM RDB$RELATION_FIELDS WHERE RDB$RELATION_NAME = 'CONTAS'")
    for row in cur.fetchall():
        print(row)
except Exception as e:
    print("ERROR:", e)
