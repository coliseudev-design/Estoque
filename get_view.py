import fdb
import sys

if len(sys.argv) < 2:
    print("Usage: python get_view.py <VIEW_NAME>")
    sys.exit(1)

view_name = sys.argv[1].upper()

con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey')
cur = con.cursor()
cur.execute("SELECT RDB$VIEW_SOURCE FROM RDB$RELATIONS WHERE TRIM(RDB$RELATION_NAME) = ?", (view_name,))
row = cur.fetchone()
if row and row[0]:
    with open(f'{view_name}_source.txt', 'w') as f:
        f.write(row[0])
    print(f"Saved to {view_name}_source.txt")
else:
    print(f"View {view_name} not found")
