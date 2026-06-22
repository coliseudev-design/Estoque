import fdb
from decimal import Decimal

con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey')
cur = con.cursor()

cur.execute("SELECT * FROM DASH_FILIAIS")
col_names = [col[0].lower() for col in cur.description]
rows = cur.fetchall()
print(f"Found {len(rows)} rows in DASH_FILIAIS:")
for r in rows:
    row_dict = dict(zip(col_names, r))
    print(row_dict)

con.close()
