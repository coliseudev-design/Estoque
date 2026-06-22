import fdb

try:
    conn = fdb.connect(dsn=r'C:\Coliseu\Data\PIVETA.FDB', user='SYSDBA', password='masterkey', charset='WIN1252')
    cur = conn.cursor()
    
    # Check structure of FUNCIONARIOS
    print("Checking FUNCIONARIOS structure:")
    cur.execute("SELECT RDB$FIELD_NAME FROM RDB$RELATION_FIELDS WHERE RDB$RELATION_NAME = 'FUNCIONARIOS' AND RDB$FIELD_NAME IN ('ID_FUNCIONARIO', 'NOME', 'ID_EMPRESA', 'MOB_ACESSO')")
    for row in cur:
        print(f"Column: {row[0].strip()}")
        
    print("\nFetching unique ID_EMPRESA from FUNCIONARIOS:")
    cur.execute("SELECT DISTINCT ID_EMPRESA FROM FUNCIONARIOS")
    for row in cur:
        print(f"ID_EMPRESA value: {row[0]}")
        
    print("\nFetching sample sellers with MOB_ACESSO = 1:")
    cur.execute("SELECT ID_FUNCIONARIO, NOME, MOB_ACESSO, ID_EMPRESA FROM FUNCIONARIOS WHERE MOB_ACESSO = 1")
    for row in cur:
        print(f"ID={row[0]} | Name={row[1].strip() if row[1] else 'None'} | MOB_ACESSO={row[2]} | ID_EMPRESA={row[3]}")
        
    conn.close()
except Exception as e:
    print("Error:", e)
