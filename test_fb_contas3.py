import fdb
try:
    con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey', charset='WIN1252')
    cur = con.cursor()
    cur.execute("""
            SELECT FIRST 2000
                con.ID_CONTA                                             AS id_firebird,
                CASE WHEN con.DC = 'C' THEN 'RECEBER' ELSE 'PAGAR' END  AS tipo,
                COALESCE(con.DESCRICAO, '')                              AS descricao,
                con.ID_CLIENTE                                           AS cliente_id_firebird,
                con.DATA_EMISSAO                                         AS data_emissao,
                con.DATA_VENCIMENTO                                      AS data_vencimento,
                con.DATA_PAGAMENTO                                       AS data_pagamento,
                COALESCE(con.VALOR, 0)                                   AS valor,
                COALESCE(con.VALOR_PAGO, 0)                              AS valor_pago,
                (CASE WHEN con.BAIXA = 1 THEN 'PAGO' ELSE 'ABERTO' END) AS status_pagamento
            FROM CONTAS con
            WHERE con.DATA_EMISSAO IS NOT NULL
            ORDER BY con.ID_CONTA DESC
    """)
    rows = cur.fetchall()
    print("Fetched:", len(rows))
    print("Query Full OK!")
except Exception as e:
    print("ERROR:", e)
