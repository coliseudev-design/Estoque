import fdb
con = fdb.connect(dsn=r"C:\Coliseu\Data\PIVETA.FDB", user="SYSDBA", password="masterkey")
cur = con.cursor()
cur.execute("SELECT RDB$RELATION_NAME, RDB$FIELD_NAME FROM RDB$RELATION_FIELDS WHERE RDB$FIELD_NAME LIKE '%EMPRESA%'")
for row in cur:
    print(f"{row[0].strip()}.{row[1].strip()}")
