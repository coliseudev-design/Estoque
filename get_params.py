import fdb

con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey')
cur = con.cursor()
cur.execute("SELECT RDB$PARAMETER_NAME, RDB$PARAMETER_NUMBER FROM RDB$PROCEDURE_PARAMETERS WHERE TRIM(RDB$PROCEDURE_NAME) = 'MOB_CADASTRAR_PEDIDO' AND RDB$PARAMETER_TYPE = 0 ORDER BY RDB$PARAMETER_NUMBER")
rows = cur.fetchall()
for r in rows:
    print(f"{r[1]}: {r[0].strip()}")
