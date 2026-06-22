import sys
sys.stdout.reconfigure(encoding='utf-8')

import fdb

conn = fdb.connect(
    dsn=r"C:\Coliseu\Data\PIVETA.FDB",
    user="SYSDBA",
    password="masterkey",
    charset="WIN1252"
)

cursor = conn.cursor()

# 1. Valores distintos do campo TIPO com contagem
print("=== Valores distintos de CONTAS.TIPO ===")
cursor.execute("""
    SELECT TIPO, COUNT(*) as total
    FROM CONTAS
    GROUP BY TIPO
    ORDER BY TIPO
""")
for row in cursor.fetchall():
    print(f"  TIPO = {str(row[0]):>5}  ->  {row[1]} registros")

# 2. Tenta ver se existe tabela de lookup para TIPO
print("\n=== Verificando se existe tabela TIPOS_CONTA ou similar ===")
cursor.execute("""
    SELECT TRIM(RDB$RELATION_NAME)
    FROM RDB$RELATIONS
    WHERE RDB$SYSTEM_FLAG = 0
      AND (TRIM(RDB$RELATION_NAME) CONTAINING 'TIPO'
        OR TRIM(RDB$RELATION_NAME) CONTAINING 'CONTA')
    ORDER BY 1
""")
tabelas = cursor.fetchall()
for t in tabelas:
    print(f"  {t[0]}")

conn.close()
print("\nPronto!")
