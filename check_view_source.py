import sys
sys.stdout.reconfigure(encoding='utf-8')
import fdb

conn = fdb.connect(dsn=r'C:\Coliseu\Data\PIVETA.FDB', user='SYSDBA', password='masterkey', charset='WIN1252')
cur = conn.cursor()

# Lê o source da view DASH_VENDAS
cur.execute("""
    SELECT TRIM(RDB$RELATION_NAME), TRIM(RDB$VIEW_SOURCE)
    FROM RDB$RELATIONS
    WHERE RDB$RELATION_NAME = 'DASH_VENDAS'
""")
row = cur.fetchone()
if row:
    print("=== DASH_VENDAS - linhas com CUSTO ===")
    for line in (row[1] or '').splitlines():
        if 'CUSTO' in line.upper():
            print(f"  {line}")

# Lê o source da view DASH_VENDAS_ITENS
cur.execute("""
    SELECT TRIM(RDB$RELATION_NAME), TRIM(RDB$VIEW_SOURCE)
    FROM RDB$RELATIONS
    WHERE RDB$RELATION_NAME = 'DASH_VENDAS_ITENS'
""")
row = cur.fetchone()
if row:
    print()
    print("=== DASH_VENDAS_ITENS - linhas com CUSTO ===")
    for line in (row[1] or '').splitlines():
        if 'CUSTO' in line.upper():
            print(f"  {line}")

conn.close()
