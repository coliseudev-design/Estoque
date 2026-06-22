import fdb
import sys

if len(sys.argv) < 2:
    print("Usage: python get_cols_any.py <TABLE_NAME>")
    sys.exit(1)

table_name = sys.argv[1].upper()

con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey')
cur = con.cursor()
cur.execute("SELECT RDB$FIELD_NAME FROM RDB$RELATION_FIELDS WHERE TRIM(RDB$RELATION_NAME) = ?", (table_name,))
for row in cur.fetchall():
    print(row[0].strip())
