import sys
sys.stdout.reconfigure(encoding='utf-8')
import fdb

conn = fdb.connect(dsn=r'C:\Coliseu\Data\PIVETA.FDB', user='SYSDBA', password='masterkey', charset='WIN1252')
cur = conn.cursor()

query = """
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

try:
    cur.execute(query)
    desc = [col[0] for col in cur.description]
    print("Columns:", desc)
    rows = cur.fetchall()
    print("Rows:")
    for row in rows:
        print(row)
except Exception as e:
    print("Error:", e)

conn.close()
