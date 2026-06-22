import sys
sys.stdout.reconfigure(encoding='utf-8')
import fdb

conn = fdb.connect(
    dsn=r"C:\Coliseu\Data\PIVETA.FDB",
    user="SYSDBA",
    password="masterkey",
    charset="WIN1252"
)
cur = conn.cursor()

# Busca o label TITULO COMUM em SPs
print("=== Buscando 'TITULO COMUN' ou 'TITULO COM' em SPs ===")
cur.execute("""
    SELECT TRIM(rdb$procedure_name), TRIM(rdb$procedure_source)
    FROM rdb$procedures
    WHERE rdb$system_flag = 0
      AND rdb$procedure_source CONTAINING 'TITULO COM'
""")
for name, src in cur.fetchall():
    lines = [l.strip() for l in (src or '').splitlines() if 'TITULO' in l.upper()]
    if lines:
        print(f"\n-- SP: {name}")
        for l in lines[:15]:
            print(f"   {l}")

# Busca em Views
cur.execute("""
    SELECT TRIM(rdb$relation_name), TRIM(rdb$view_source)
    FROM rdb$relations
    WHERE rdb$system_flag = 0
      AND rdb$view_source IS NOT NULL
      AND rdb$view_source CONTAINING 'TITULO COM'
""")
for name, src in cur.fetchall():
    lines = [l.strip() for l in (src or '').splitlines() if 'TITULO' in l.upper()]
    if lines:
        print(f"\n-- VIEW: {name}")
        for l in lines[:15]:
            print(f"   {l}")

conn.close()
print("\nPronto!")
