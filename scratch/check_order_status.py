import fdb
from datetime import date

con = fdb.connect(dsn=r"C:\Coliseu\Data\PIVETA.FDB", user="SYSDBA", password="masterkey")
cur = con.cursor()

print("--- 10 LATEST PEDIDOS ---")
cur.execute("""
    SELECT FIRST 10 ID_PEDIDO, PEDIDO, ID_VENDEDOR, ID_CLIENTE, ID_DEPTO, STATUS, TIPO, ID_NATUREZA, DATA_HORA, DATA_VENCIMENTO, VALOR_PEDIDO
    FROM PEDIDOS
    ORDER BY ID_PEDIDO DESC
""")
for row in cur.fetchall():
    print(f"ID: {row[0]}, Pedido: {row[1]}, Vendedor: {row[2]}, Cliente: {row[3]}, Depto: {row[4]}, Status: {row[5]}, Tipo: {row[6]}, Natureza: {row[7]}, DataHora: {row[8]}, Venc: {row[9]}, Valor: {row[10]}")

print("\n--- NATUREZA OPERACAO FOR LATEST NATURES ---")
cur.execute("""
    SELECT ID_NATUREZA, DESCRICAO, CALC_COMISSAO, PROCESSO
    FROM NATUREZA_OPERACAO
""")
natures = {row[0]: (row[1], row[2], row[3]) for row in cur.fetchall()}
for id_nat, details in list(natures.items())[:20]:
    print(f"ID: {id_nat}, Desc: {details[0]}, CalcComissao: {details[1]}, Processo: {details[2]}")

# Let's check Roberson (vendedor 105) orders today/yesterday
print("\n--- VENDEDOR 105 PEDIDOS TODAY/YESTERDAY ---")
cur.execute("""
    SELECT ID_PEDIDO, PEDIDO, STATUS, TIPO, ID_NATUREZA, ID_DEPTO, DATA_VENCIMENTO, VALOR_PEDIDO
    FROM PEDIDOS
    WHERE ID_VENDEDOR = 105 AND DATA_VENCIMENTO >= '2026-05-19'
""")
for row in cur.fetchall():
    nat_desc = natures.get(row[4], ("DESCONHECIDO", None, None))
    print(f"ID: {row[0]}, Pedido: {row[1]}, Status: {row[2]}, Tipo: {row[3]}, Natureza: {row[4]} ({nat_desc[0]}, CalcComissao: {nat_desc[1]}), Depto: {row[5]}, Venc: {row[6]}, Valor: {row[7]}")

con.close()
