import fdb

con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey')
cur = con.cursor()
cur.execute("SELECT RDB$PROCEDURE_SOURCE FROM RDB$PROCEDURES WHERE TRIM(RDB$PROCEDURE_NAME) = 'MOB_CADASTRAR_PEDIDO'")
row = cur.fetchone()
if row:
    with open('sp_source.txt', 'w') as f:
        f.write(row[0])
    print("Saved to sp_source.txt")
else:
    print("Not found")
