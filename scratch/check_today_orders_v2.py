import fdb
from datetime import datetime

con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey')
cur = con.cursor()

print("--- ALL ORDERS ON 2026-05-21 ---")
cur.execute("""
    SELECT p.ID_PEDIDO, p.PEDIDO, p.STATUS, p.TIPO, p.DATA_HORA, p.DATA_VENCIMENTO, p.ID_DEPTO, p.ID_VENDEDOR, p.VALOR_PEDIDO,
           p.ID_CLIENTE, c.NOME as CLIENTE_NOME, n.DESCRICAO as NATUREZA_DESC, n.CALC_COMISSAO, n.PROCESSO
    FROM PEDIDOS p
    LEFT JOIN CLIENTES c ON c.ID_CLIENTE = p.ID_CLIENTE
    LEFT JOIN NATUREZA_OPERACAO n ON n.ID_NATUREZA = p.ID_NATUREZA
    WHERE p.DATA_VENCIMENTO = '2026-05-21' AND p.TIPO = 1
""")
columns = [col[0] for col in cur.description]
rows = cur.fetchall()
for row in rows:
    row_dict = dict(zip(columns, row))
    print(f"Pedido: {row_dict['PEDIDO']} | ID: {row_dict['ID_PEDIDO']} | Status: {row_dict['STATUS']} | Vendedor: {row_dict['ID_VENDEDOR']} | Valor: {row_dict['VALOR_PEDIDO']} | Cliente: {row_dict['CLIENTE_NOME']} | Natureza: {row_dict['NATUREZA_DESC']} (CalcCom: {row_dict['CALC_COMISSAO']})")
    
    # Check if there is estoque record for this order
    cur.execute("""
        SELECT e.ID_ESTOQUE, e.VALOR_TOTAL, e.VALOR_COMISSAO, e.STATUS, e.MOVC
        FROM ESTOQUE e
        WHERE e.ID_PEDIDO = ?
    """, (row_dict['ID_PEDIDO'],))
    est_cols = [col[0] for col in cur.description]
    est_rows = cur.fetchall()
    print(f"  Estoque entries ({len(est_rows)}):")
    for est in est_rows:
        print(f"    {dict(zip(est_cols, est))}")

con.close()
