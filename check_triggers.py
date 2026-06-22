import fdb
con = fdb.connect(dsn=r"C:\Coliseu\Data\PIVETA.FDB", user="SYSDBA", password="masterkey")
cur = con.cursor()
cur.execute("SELECT RDB$TRIGGER_NAME FROM RDB$TRIGGERS WHERE RDB$RELATION_NAME = 'PEDIDO_ITENS' AND RDB$SYSTEM_FLAG = 0")
for row in cur:
    print(row[0].strip())
