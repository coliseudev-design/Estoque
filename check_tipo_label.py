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

# Tenta encontrar o label do TIPO lendo a stored procedure ou view que os exibe
# Busca em procedures que contenham 'TIPO' e 'CONTAS'
print("=== Source de SP/Views com mapeamento de TIPO ===")
cur.execute("""
    SELECT TRIM(rdb$procedure_name), TRIM(rdb$procedure_source)
    FROM rdb$procedures
    WHERE rdb$system_flag = 0
      AND rdb$procedure_source CONTAINING 'TITULO'
""")
for row in cur.fetchall():
    name, src = row
    # Mostra apenas as linhas que contêm TIPO ou TITULO
    lines = [l for l in (src or '').splitlines() if 'TIPO' in l.upper() or 'TITULO' in l.upper()]
    if lines:
        print(f"\n-- SP: {name}")
        for l in lines[:20]:
            print(f"   {l}")

# Busca em views
cur.execute("""
    SELECT TRIM(rdb$relation_name), TRIM(rdb$view_source)
    FROM rdb$relations
    WHERE rdb$system_flag = 0
      AND rdb$view_source IS NOT NULL
      AND rdb$view_source CONTAINING 'TITULO'
""")
for row in cur.fetchall():
    name, src = row
    lines = [l for l in (src or '').splitlines() if 'TIPO' in l.upper() or 'TITULO' in l.upper()]
    if lines:
        print(f"\n-- VIEW: {name}")
        for l in lines[:20]:
            print(f"   {l}")

conn.close()
print("\nPronto!")
