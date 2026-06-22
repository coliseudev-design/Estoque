import sys
sys.stdout.reconfigure(encoding='utf-8')
import fdb
from datetime import date

hoje = date.today()
print(f"=== Data de hoje: {hoje} ===\n")

conn = fdb.connect(dsn=r'C:\Coliseu\Data\PIVETA.FDB', user='SYSDBA', password='masterkey', charset='WIN1252')
cur = conn.cursor()

# 1. Vendas de hoje no Firebird (tabela PEDIDOS bruta)
print("=== 1. PEDIDOS hoje (tabela bruta) ===")
cur.execute("""
    SELECT COUNT(*), COALESCE(SUM(VALOR_PEDIDO), 0)
    FROM PEDIDOS
    WHERE CAST(DATA_HORA AS DATE) = CURRENT_DATE
      AND STATUS IN (0, 1, 2)
      AND TIPO = 1
""")
r = cur.fetchone()
print(f"  Pedidos: {r[0]}  |  Total: R$ {r[1]:.2f}")

# 2. Vendas de hoje via VIEW DASH_VENDAS
print()
print("=== 2. DASH_VENDAS hoje (view) ===")
cur.execute("""
    SELECT COUNT(*), COALESCE(SUM(valor_total), 0), COALESCE(SUM(valor_custo), 0)
    FROM DASH_VENDAS
    WHERE data_venda = CURRENT_DATE
""")
r = cur.fetchone()
print(f"  Registros: {r[0]}  |  Total: R$ {r[1]:.2f}  |  Custo: R$ {r[2]:.2f}")

# 3. Ultimas 5 vendas da view para ver o data_venda
print()
print("=== 3. Ultimas 5 vendas na DASH_VENDAS ===")
cur.execute("""
    SELECT FIRST 5 id_firebird, data_venda, valor_total, status
    FROM DASH_VENDAS
    ORDER BY id_firebird DESC
""")
for row in cur.fetchall():
    print(f"  ID {row[0]} | data={row[1]} | total={row[2]:.2f} | status={row[3]}")

conn.close()
