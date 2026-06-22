import sys
sys.stdout.reconfigure(encoding='utf-8')
import fdb

sql = """
CREATE OR ALTER VIEW DASH_FILIAIS AS
SELECT
    d.ID_DEPTO                                               AS depto_id,
    COALESCE(TRIM(d.DESCRICAO), '')                          AS nome,
    COALESCE(TRIM(e.CNPJ), '')                               AS documento,
    COALESCE(TRIM(d.OP_ESTOQUE), '')                         AS centro_custo,
    COALESCE(c.ID_EMPRESA, 1)                                AS empresa_erp,
    CASE WHEN c.ID_EMPRESA = 1 THEN 1 ELSE 0 END             AS is_default
FROM DEPARTAMENTOS d
LEFT JOIN CONFIG c ON c.DEPTO_PADRAO = d.ID_DEPTO
LEFT JOIN EMPRESA e ON e.ID_EMPRESA = c.ID_EMPRESA
"""

print("Connecting to Firebird...")
con = fdb.connect(dsn=r'C:\Coliseu\Data\PIVETA.FDB', user='SYSDBA', password='masterkey', charset='WIN1252')
cur = con.cursor()

try:
    print("Recreating view DASH_FILIAIS...")
    cur.execute(sql)
    con.commit()
    print("Successfully recreated view DASH_FILIAIS!")
except Exception as e:
    print("Error recreating view:", e)
    con.rollback()

try:
    print("\nVerifying DASH_FILIAIS rows:")
    cur.execute("SELECT * FROM DASH_FILIAIS")
    desc = [col[0] for col in cur.description]
    print("Columns:", desc)
    rows = cur.fetchall()
    for r in rows:
        print(r)
except Exception as e:
    print("Error querying view:", e)

con.close()
