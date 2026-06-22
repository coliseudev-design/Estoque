import fdb
import sys

if len(sys.argv) < 2:
    print("Usage: python get_sp_any.py <SP_NAME>")
    sys.exit(1)

sp_name = sys.argv[1].upper()

con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey')
cur = con.cursor()
cur.execute("SELECT RDB$PROCEDURE_SOURCE FROM RDB$PROCEDURES WHERE TRIM(RDB$PROCEDURE_NAME) = ?", (sp_name,))
row = cur.fetchone()
if row:
    with open(f'{sp_name}_source.txt', 'w') as f:
        f.write(row[0])
    print(f"Saved to {sp_name}_source.txt")
else:
    print(f"SP {sp_name} not found")
