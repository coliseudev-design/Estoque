import fdb
con = fdb.connect(dsn=r"C:\Coliseu\Data\PIVETA.FDB", user="SYSDBA", password="masterkey")
cur = con.cursor()
cur.execute("SELECT RDB$PROCEDURE_SOURCE FROM RDB$PROCEDURES WHERE RDB$PROCEDURE_NAME = 'MOB_CADASTRAR_PEDIDO_ITEM'")
row = cur.fetchone()
if row:
    print(row[0])
else:
    print("Not found")
