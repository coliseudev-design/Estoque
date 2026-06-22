import fdb

con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey')
cur = con.cursor()

try:
    cur.execute("SELECT TRIM('hello ') FROM rdb$database")
    print("TRIM('hello '):", repr(cur.fetchone()[0]))
except Exception as e:
    print("TRIM failed:", e)

try:
    cur.execute("""
        SELECT TRIM(CASE 1
            WHEN 1 THEN 'ABERTO'
            ELSE 'CANCELADO'
        END) FROM rdb$database
    """)
    print("TRIM(CASE...):", repr(cur.fetchone()[0]))
except Exception as e:
    print("TRIM CASE failed:", e)

con.close()
