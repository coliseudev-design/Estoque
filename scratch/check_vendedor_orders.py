import fdb

con = fdb.connect(dsn=r"C:\Coliseu\Data\PIVETA.FDB", user="SYSDBA", password="masterkey")
cur = con.cursor()

cur.execute("""
    SELECT DISTINCT P.ID_PEDIDO, P.PEDIDO, P.DATA_VENCIMENTO, P.VALOR_PEDIDO, P.STATUS, P.ID_MOBILE
    FROM PEDIDOS P
    INNER JOIN ESTOQUE E ON E.ID_PEDIDO = P.ID_PEDIDO
    LEFT JOIN NATUREZA_OPERACAO N ON N.ID_NATUREZA = P.ID_NATUREZA
    WHERE P.ID_VENDEDOR = 105 
      AND P.STATUS = 2 
      AND P.TIPO = 1 
      AND E.MOVC = 1 
      AND E.STATUS <> 9
      AND N.CALC_COMISSAO = 1
      AND EXTRACT(MONTH FROM P.DATA_VENCIMENTO) = 5
      AND EXTRACT(YEAR FROM P.DATA_VENCIMENTO) = 2026
    ORDER BY P.ID_PEDIDO DESC
""")

cols = [desc[0] for desc in cur.description]
print("Orders included in MINHASVENDAS for month 5:")
for row in cur.fetchall():
    print(dict(zip(cols, row)))
