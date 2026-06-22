import fdb

con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey')
cur = con.cursor()
cur.execute("SELECT count(*) FROM RDB$PROCEDURE_PARAMETERS WHERE TRIM(RDB$PROCEDURE_NAME) = 'MOB_CADASTRAR_PEDIDO' AND RDB$PARAMETER_TYPE = 0")
row = cur.fetchone()
print(f"ParamCount: {row[0]}")
