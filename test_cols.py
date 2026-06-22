import fdb
try:
    con = fdb.connect(dsn='localhost:C:/Coliseu/Data/PIVETA.FDB', user='SYSDBA', password='masterkey')
    cur = con.cursor()
    cur.execute("SELECT RDB$FIELD_NAME FROM RDB$RELATION_FIELDS WHERE RDB$RELATION_NAME = 'PEDIDO_ITENS'")
    pi_cols = [r[0].strip() for r in cur.fetchall()]
    
    sp_cols = ['ID_PEDIDO', 'ID_ITEM', 'ID_PRODUTO', 'DESCRICAO', 'UNIDADE', 'QTDE', 'VALOR_UNITARIO', 'CF', 'VALOR_TOTAL', 'VALOR_FINAL', 'VALOR_FINAL_UN', 'TIPO', 'VALOR_CUSTO', 'CODIGO_BARRA', 'TIPO_UNIDADE', 'DESCONTO', 'STATUS', 'ICMS', 'REDUCAO_ICMS', 'TRIBUTACAO', 'BASE_CALCULO', 'VALOR_ICMS', 'BASE_ICMS_SUB', 'VALOR_ICMS_SUB', 'PESO', 'CFOP', 'PIS_CST', 'COFINS_CST', 'IPI_CST', 'PIS', 'COFINS', 'IPI', 'CSOSN', 'ORIGEM', 'LUCRO', 'LUCRO_MAX', 'ENTREGAR', 'VALOR_IPI', 'BASE_IPI', 'BASE_PIS', 'BASE_COFINS']
    
    print('Checking PEDIDO_ITENS columns...')
    for c in sp_cols:
        if c not in pi_cols:
            print(f'MISSING in PI: {c}')
            
    cur.execute("SELECT RDB$FIELD_NAME FROM RDB$RELATION_FIELDS WHERE RDB$RELATION_NAME = 'PRODUTOS'")
    pr_cols = [r[0].strip() for r in cur.fetchall()]
    sp_pr_cols = ['ORIGEM_MERCADORIA', 'TRIBUTACAO', 'PRECO_CUSTO', 'CODIGO_BARRA', 'ICMS', 'REDUCAO', 'PESO', 'CFOP_E', 'PIS_CST', 'COFINS_CST', 'IPI_CST', 'PIS', 'COFINS', 'IPI', 'CSOSN', 'MARGEM_LUCRO', 'MARGEM_MAXIMA']
    print('Checking PRODUTOS columns...')
    for c in sp_pr_cols:
        if c not in pr_cols:
            print(f'MISSING in PR: {c}')
except Exception as e:
    print('Error:', e)
