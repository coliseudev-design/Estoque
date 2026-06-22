import sys
sys.stdout.reconfigure(encoding='utf-8')
import fdb

conn = fdb.connect(dsn=r'C:\Coliseu\Data\PIVETA.FDB', user='SYSDBA', password='masterkey', charset='WIN1252')
cur = conn.cursor()

views = {
    "DASH_VENDAS": """
        CREATE OR ALTER VIEW DASH_VENDAS AS
        SELECT
            p.ID_PEDIDO                                              AS id_firebird,
            CAST(p.ID_PEDIDO AS VARCHAR(20))                         AS numero_pedido,
            CAST(p.DATA_HORA AS DATE)                                AS data_venda,
            p.DATA_HORA_PROC                                         AS data_hora_proc,
            p.ID_CLIENTE                                             AS cliente_id_firebird,
            p.ID_VENDEDOR                                            AS vendedor_id_firebird,
            MAX((CASE WHEN nat.TIPO = 2 THEN -1 ELSE 1 END) * (COALESCE(p.VALOR_PEDIDO, 0) + COALESCE(p.VALOR_FRETE, 0) + COALESCE(p.OUTRAS_DESPESAS, 0) + COALESCE(p.VALOR_ACRESCIMO, 0) + COALESCE(p.VALOR_IPI, 0) + COALESCE(p.VALOR_ICMS_SUB, 0) - COALESCE(p.VALOR_DESCONTO, 0))) AS valor_total,
            (CASE WHEN nat.TIPO = 2 THEN -1 ELSE 1 END) * COALESCE(SUM(pi.VALOR_CUSTO), 0) AS valor_custo,
            (CASE WHEN nat.TIPO = 2 THEN -1 ELSE 1 END) * MAX(COALESCE(p.VALOR_DESCONTO, 0)) AS valor_desconto,
            CASE p.STATUS
                WHEN 0 THEN 'ABERTO'
                WHEN 1 THEN 'ABERTO'
                WHEN 9 THEN 'CANCELADO'
                ELSE 'FATURADO'
            END                                                      AS status,
            MAX(COALESCE(pr.MARCA, ''))                              AS marca,
            MAX(COALESCE(cat.DESCRICAO, ''))                         AS categoria,
            MAX(COALESCE(esp.DESCRICAO, 'Não Informada'))            AS especie,
            p.ID_DEPTO                                               AS depto_id,
            p.DATA_VENCIMENTO                                        AS data_vencimento,
            p.ID_NATUREZA                                            AS natureza_id,
            nat.TIPO                                                 AS natureza_tipo,
            nat.PROCESSO                                             AS natureza_processo
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
          AND (nat.PROCESSO <> 3 OR nat.PROCESSO IS NULL)
        GROUP BY p.ID_PEDIDO, p.DATA_HORA, p.DATA_HORA_PROC, p.ID_CLIENTE, p.ID_VENDEDOR, p.STATUS, p.ID_DEPTO, p.DATA_VENCIMENTO, p.ID_NATUREZA, nat.TIPO, nat.PROCESSO
    """,

    "DASH_VENDAS_ITENS": """
        CREATE OR ALTER VIEW DASH_VENDAS_ITENS AS
        SELECT
            ((pi.ID_PEDIDO * 1000) + pi.ID_ITEM)                     AS id_firebird,
            pi.ID_PEDIDO                                             AS venda_id_firebird,
            pi.ID_PRODUTO                                            AS produto_id_firebird,
            (CASE WHEN nat.TIPO = 2 THEN -1 ELSE 1 END) * COALESCE(pi.QTDE, 0) AS quantidade,
            COALESCE(pi.VALOR_UNITARIO, 0)                           AS preco_unitario,
            COALESCE(pi.VALOR_CUSTO, 0)                              AS custo_unitario,
            (CASE WHEN nat.TIPO = 2 THEN -1 ELSE 1 END) * COALESCE(pi.VALOR_TOTAL, 0) AS valor_total,
            COALESCE(f.NOME, '')                                     AS vendedor,
            COALESCE(pr.DESCRICAO, '')                               AS produto,
            COALESCE(pr.MARCA, '')                                   AS marca,
            COALESCE(cat.DESCRICAO, '')                              AS categoria,
            p.ID_DEPTO                                               AS depto_id,
            p.ID_NATUREZA                                            AS natureza_id,
            nat.TIPO                                                 AS natureza_tipo,
            nat.PROCESSO                                             AS natureza_processo
        FROM PEDIDO_ITENS pi
        JOIN PEDIDOS p ON p.ID_PEDIDO = pi.ID_PEDIDO
        LEFT JOIN PRODUTOS pr ON pr.ID_PRODUTO = pi.ID_PRODUTO
        LEFT JOIN CATEGORIAS cat ON cat.ID_CATEGORIA = pr.ID_CATEGORIA
        LEFT JOIN FUNCIONARIOS f ON f.ID_FUNCIONARIO = p.ID_VENDEDOR
        LEFT JOIN NATUREZA_OPERACAO nat ON nat.ID_NATUREZA = p.ID_NATUREZA
        WHERE p.STATUS IN (0, 1, 2, 9)
          AND p.TIPO = 1
          AND nat.OPERACAO IN (1, 6, 12)
          AND (nat.PROCESSO <> 3 OR nat.PROCESSO IS NULL)
    """,
}

for name, ddl in views.items():
    try:
        cur.execute(ddl)
        print(f"OK - View {name} atualizada!")
    except Exception as e:
        print(f"ERRO - {name}: {e}")

conn.commit()
conn.close()

print()
print("Verificando resultado...")

# Verifica
conn2 = fdb.connect(dsn=r'C:\Coliseu\Data\PIVETA.FDB', user='SYSDBA', password='masterkey', charset='WIN1252')
cur2 = conn2.cursor()
cur2.execute("SELECT FIRST 3 id_firebird, valor_total, valor_custo FROM DASH_VENDAS ORDER BY id_firebird DESC")
rows = cur2.fetchall()
print("DASH_VENDAS (apos update):")
for r in rows:
    print(f"  ID {r[0]}: total={r[1]:.2f}  custo={r[2]:.2f}")

cur2.execute("SELECT FIRST 3 id_firebird, preco_unitario, custo_unitario FROM DASH_VENDAS_ITENS ORDER BY id_firebird DESC")
rows = cur2.fetchall()
print("DASH_VENDAS_ITENS (apos update):")
for r in rows:
    print(f"  ID {r[0]}: preco={r[1]:.2f}  custo={r[2]:.2f}")

conn2.close()
