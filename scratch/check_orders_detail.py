import fdb

con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey', charset='WIN1252')
cur = con.cursor()

ids = [529698, 529699]
for pid in ids:
    print(f"\n=== Pedido {pid} ===")
    cur.execute("""
        SELECT ID_PEDIDO, PEDIDO, ID_VENDEDOR, ID_DEPTO, STATUS, TIPO, DATA_VENCIMENTO, DATA_HORA, DESCONTO, ID_NATUREZA
        FROM PEDIDOS
        WHERE ID_PEDIDO = ?
    """, (pid,))
    row = cur.fetchone()
    if row:
        cols = ['ID_PEDIDO', 'PEDIDO', 'ID_VENDEDOR', 'ID_DEPTO', 'STATUS', 'TIPO', 'DATA_VENCIMENTO', 'DATA_HORA', 'DESCONTO', 'ID_NATUREZA']
        for col, val in zip(cols, row):
            print(f"  {col}: {val}")
        
        # Check vendedor info
        vendedor_id = row[2]
        cur.execute("SELECT ID_FUNCIONARIO, NOME, MOB_ACESSO, ID_EMPRESA FROM FUNCIONARIOS WHERE ID_FUNCIONARIO = ?", (vendedor_id,))
        v = cur.fetchone()
        if v:
            print(f"  Vendedor: ID={v[0]}, Nome={v[1].strip()}, MOB_ACESSO={v[2]}, ID_EMPRESA={v[3]}")
        else:
            print(f"  Vendedor ID {vendedor_id} não encontrado!")
            
        # Check natureza_operacao info
        nat_id = row[9]
        cur.execute("SELECT ID_NATUREZA, DESCRICAO, CALC_COMISSAO, PROCESSO FROM NATUREZA_OPERACAO WHERE ID_NATUREZA = ?", (nat_id,))
        n = cur.fetchone()
        if n:
            print(f"  Natureza: ID={n[0]}, Desc={n[1].strip()}, CALC_COMISSAO={n[2]}, PROCESSO={n[3]}")
        else:
            print(f"  Natureza ID {nat_id} não encontrada!")
            
        # Check if there are estoque rows for this order
        cur.execute("SELECT COUNT(*), SUM(STATUS) FROM ESTOQUE WHERE ID_PEDIDO = ?", (pid,))
        e = cur.fetchone()
        print(f"  Estoque: Qtd={e[0]}, SumStatus={e[1]}")
        if e[0] > 0:
            cur.execute("SELECT FIRST 3 ID_PRODUTO, VALOR_TOTAL, VALOR_COMISSAO, STATUS, MOVC FROM ESTOQUE WHERE ID_PEDIDO = ?", (pid,))
            for est_row in cur.fetchall():
                print(f"    Estoque item: Prod={est_row[0]}, Total={est_row[1]}, Comis={est_row[2]}, Status={est_row[3]}, MOVC={est_row[4]}")
    else:
        print("  Pedido não encontrado!")

con.close()
