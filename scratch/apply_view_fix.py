import fdb

sql = """
CREATE OR ALTER VIEW DASH_VENDAS AS
SELECT
    p.ID_PEDIDO                                              AS id_firebird,
    CAST(p.ID_PEDIDO AS VARCHAR(20))                         AS numero_pedido,
    CAST(p.DATA_HORA AS DATE)                                AS data_venda,
    p.ID_CLIENTE                                             AS cliente_id_firebird,
    p.ID_VENDEDOR                                            AS vendedor_id_firebird,
    MAX(COALESCE(p.VALOR_PEDIDO, 0) + COALESCE(p.VALOR_FRETE, 0) + COALESCE(p.OUTRAS_DESPESAS, 0) + COALESCE(p.VALOR_ACRESCIMO, 0) + COALESCE(p.VALOR_IPI, 0) + COALESCE(p.VALOR_ICMS_SUB, 0) - COALESCE(p.VALOR_DESCONTO, 0)) AS valor_total,
    COALESCE(SUM(pi.VALOR_CUSTO), 0)                         AS valor_custo,
    MAX(COALESCE(p.VALOR_DESCONTO, 0))                       AS valor_desconto,
    TRIM(CASE p.STATUS 
        WHEN 0 THEN 'ABERTO'
        WHEN 1 THEN 'ABERTO'
        WHEN 9 THEN 'CANCELADO' 
        ELSE 'FATURADO' 
    END)                                                     AS status,
    MAX(COALESCE(pr.MARCA, ''))                              AS marca,
    MAX(COALESCE(cat.DESCRICAO, ''))                         AS categoria,
    MAX(COALESCE(esp.DESCRICAO, 'Não Informada'))            AS especie,
    p.ID_DEPTO                                               AS depto_id
FROM PEDIDOS p
JOIN PEDIDO_ITENS pi ON pi.ID_PEDIDO = p.ID_PEDIDO
LEFT JOIN PRODUTOS pr ON pr.ID_PRODUTO = pi.ID_PRODUTO
LEFT JOIN CATEGORIAS cat ON cat.ID_CATEGORIA = pr.ID_CATEGORIA
LEFT JOIN PEDIDOS_DOCS pd ON pd.ID_PEDIDO = p.ID_PEDIDO
LEFT JOIN ESPECIE_PGTO esp ON esp.ID_ESPECIE = pd.ID_ESPECIE
LEFT JOIN NATUREZA_OPERACAO nat ON nat.ID_NATUREZA = p.ID_NATUREZA
WHERE p.STATUS IN (0, 1, 2, 9)
  AND p.TIPO = 1
  AND nat.OPERACAO IN (1, 6, 12)
  AND (nat.TIPO <> 2 OR nat.TIPO IS NULL)
  AND (nat.PROCESSO <> 3 OR nat.PROCESSO IS NULL)
GROUP BY p.ID_PEDIDO, p.DATA_HORA, p.ID_CLIENTE, p.ID_VENDEDOR, p.STATUS, p.ID_DEPTO
"""

print("Connecting to Firebird...")
con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey')
cur = con.cursor()

try:
    print("Recreating view DASH_VENDAS with TRIM(status)...")
    cur.execute(sql)
    con.commit()
    print("Successfully recreated view DASH_VENDAS!")
except Exception as e:
    print("Error recreating view:", e)
    con.rollback()

try:
    print("\nVerifying rows for orders 529692-529696:")
    cur.execute("SELECT id_firebird, status FROM DASH_VENDAS WHERE id_firebird >= 529692")
    rows = cur.fetchall()
    for r in rows:
        print(f"Order: {int(r[0])}, Status: {repr(r[1])}")
except Exception as e:
    print("Error querying view:", e)

con.close()
