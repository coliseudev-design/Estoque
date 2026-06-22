import fdb

con = fdb.connect(dsn=r"C:\Coliseu\Data\PIVETA.FDB", user="SYSDBA", password="masterkey")
cur = con.cursor()

print("Executing MINHASVENDAS with correct order: VENDEDOR=105, MES=5, ANO=2026, DATA='20.05.2026'...")
try:
    cur.execute("EXECUTE PROCEDURE MINHASVENDAS(105, 5, 2026, '20.05.2026')")
    row = cur.fetchone()
    cols = [desc[0] for desc in cur.description]
    print(dict(zip(cols, row)))
except Exception as ex:
    print(f"Error: {ex}")
