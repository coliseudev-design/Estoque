import sys
sys.stdout.reconfigure(encoding='utf-8')
import fdb

conn = fdb.connect(dsn=r'C:\Coliseu\Data\PIVETA.FDB', user='SYSDBA', password='masterkey', charset='WIN1252')
cur = conn.cursor()

print("=== 1. Verificando VALOR_CUSTO em PEDIDO_ITENS ===")
cur.execute("""
    SELECT COUNT(*) total,
           SUM(CASE WHEN VALOR_CUSTO IS NULL OR VALOR_CUSTO = 0 THEN 1 ELSE 0 END) zerados,
           SUM(CASE WHEN VALOR_CUSTO > 0 THEN 1 ELSE 0 END) com_custo,
           AVG(VALOR_CUSTO) media_custo
    FROM PEDIDO_ITENS
""")
r = cur.fetchone()
print(f"  Total itens : {r[0]}")
print(f"  Zerados     : {r[1]}")
print(f"  Com custo   : {r[2]}")
print(f"  Media custo : {r[3]}")

print()
print("=== 2. Verificando a VIEW DASH_VENDAS (execucao real) ===")
cur.execute("""
    SELECT FIRST 5
        id_firebird,
        valor_total,
        valor_custo
    FROM DASH_VENDAS
    ORDER BY id_firebird DESC
""")
rows = cur.fetchall()
if rows:
    print(f"  {'ID':>10} | {'VALOR_TOTAL':>12} | {'VALOR_CUSTO':>12}")
    print("  " + "-"*40)
    for r in rows:
        print(f"  {r[0]:>10} | {r[1]:>12.2f} | {r[2]:>12.2f}")
else:
    print("  Nenhum resultado retornado pela view!")

print()
print("=== 3. Verificando DASH_VENDAS_ITENS (execucao real) ===")
cur.execute("""
    SELECT FIRST 5
        id_firebird,
        preco_unitario,
        custo_unitario
    FROM DASH_VENDAS_ITENS
    ORDER BY id_firebird DESC
""")
rows = cur.fetchall()
if rows:
    print(f"  {'ID':>12} | {'PRECO_UN':>10} | {'CUSTO_UN':>10}")
    print("  " + "-"*38)
    for r in rows:
        print(f"  {r[0]:>12} | {r[1]:>10.2f} | {r[2]:>10.2f}")
else:
    print("  Nenhum resultado retornado pela view!")

conn.close()
print("\nPronto!")
