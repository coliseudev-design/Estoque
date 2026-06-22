import fdb
try:
    con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey', charset='WIN1252')
    cur = con.cursor()
    cur.execute("""
            SELECT FIRST 2000
                con.ID_CONTA, con.DC, con.BAIXA
            FROM CONTAS con
            WHERE con.DATA_EMISSAO IS NOT NULL
            ORDER BY con.ID_CONTA DESC
    """)
    rows = cur.fetchall()
    
    # Try the CASE statements in Python
    for row in rows:
        id_conta, dc, baixa = row
        try:
            if baixa == 1:
                pass
        except:
            print("Python error on baixa 1")
    print("Fetched:", len(rows))
    print("Query Full OK!")
except Exception as e:
    print("ERROR:", e)
