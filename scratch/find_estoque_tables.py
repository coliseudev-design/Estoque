import fdb
conn = fdb.connect(dsn=r'C:\Coliseu\Data\PIVETA.FDB', user='SYSDBA', password='masterkey')
c = conn.cursor()
c.execute("SELECT RDB$RELATION_NAME FROM RDB$RELATIONS WHERE RDB$VIEW_BLR IS NULL AND RDB$SYSTEM_FLAG = 0")
tables = [row[0].strip() for row in c.fetchall()]
estoque_tables = [t for t in tables if 'ESTOQUE' in t.upper() or 'SALDO' in t.upper() or 'FILIAL' in t.upper() or 'DEPTO' in t.upper()]
print("Tables related to estoque/saldo/filial/depto:")
print(estoque_tables)
conn.close()
