import fdb

try:
    con = fdb.connect(dsn=r"C:\Coliseu\Data\PIVETA.FDB", user="SYSDBA", password="masterkey")
    cur = con.cursor()
    
    cur.execute("SELECT ID_NATUREZA, DESCRICAO, MOB_ACESSO, MOB_ORDEM FROM NATUREZA_OPERACAO")
    rows = cur.fetchall()
    
    print(f"Total Naturezas in ERP: {len(rows)}")
    for row in rows:
        print(f"ID: {repr(row[0])} | Desc: {repr(row[1])} | Acesso: {repr(row[2])} | Ordem: {repr(row[3])}")
        
except Exception as e:
    print(f"Error connecting/querying Firebird: {e}")
