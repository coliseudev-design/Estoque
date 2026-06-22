SELECT FIRST 3
    c.ID_CLIENTE             AS id_firebird,
    COALESCE(c.NOME, '')     AS nome,
    COALESCE(c.CPF_CNPJ, '') AS documento,
    COALESCE(c.EMAIL, '')    AS email,
    COALESCE(c.CIDADE, '')   AS cidade,
    CASE WHEN COALESCE(c.AN_INATIVO, 0) = 1 THEN 0 ELSE 1 END AS ativo
FROM CLIENTES c ORDER BY c.ID_CLIENTE DESC;

SELECT FIRST 3
    P.ID_PRODUTO         AS id_firebird,
    P.CODIGO_BARRA       AS codigo,
    P.DESCRICAO          AS nome,
    P.DESCRICAO          AS descricao,
    CASE WHEN COALESCE(P.BLOQUEADO, 0) = 1 THEN 0 ELSE 1 END AS ativo
FROM PRODUTOS P WHERE P.TIPO = 2 ORDER BY P.ID_PRODUTO DESC;

SELECT FIRST 3
    ID_FUNCIONARIO AS id_firebird,
    NOME AS nome,
    '' AS email,
    MOB_ACESSO AS ativo
FROM FUNCIONARIOS WHERE MOB_ACESSO = 1;

SELECT FIRST 3
    P.ID_PEDIDO AS id_firebird,
    CAST(P.ID_PEDIDO AS VARCHAR(20)) AS numero_pedido,
    P.DATA_HORA AS data_venda,
    P.ID_CLIENTE AS cliente_id_firebird,
    P.VALOR_PEDIDO AS valor_total,
    0 AS valor_custo,
    COALESCE(P.VALOR_DESCONTO, 0) AS valor_desconto,
    CASE P.STATUS WHEN 2 THEN 'FATURADO' WHEN 9 THEN 'CANCELADO' ELSE 'PENDENTE' END AS status
FROM PEDIDOS P ORDER BY P.ID_PEDIDO DESC;

SELECT FIRST 3
    I.ID_ITEM AS id_firebird,
    I.ID_PEDIDO AS venda_id_firebird,
    I.ID_PRODUTO AS produto_id_firebird,
    I.QTDE AS quantidade,
    I.VALOR_UNITARIO AS preco_unitario,
    I.VALOR_CUSTO AS custo_unitario,
    I.VALOR_TOTAL AS valor_total
FROM PEDIDO_ITENS I ORDER BY I.ID_ITEM DESC;

SELECT FIRST 3
    T.ID_CONTA             AS id_firebird,
    'RECEBER'              AS tipo,
    'Título'               AS descricao,
    T.ID_CLIENTE           AS cliente_id_firebird,
    CURRENT_TIMESTAMP      AS data_emissao,
    T.DATA_VENCIMENTO_FMT  AS data_vencimento,
    (CASE WHEN T.BAIXA = 1 THEN T.DATA_VENCIMENTO_FMT ELSE NULL END) AS data_pagamento,
    T.VALOR_CALC           AS valor,
    (CASE WHEN T.BAIXA = 1 THEN T.VALOR_CALC ELSE 0 END) AS valor_pago,
    (CASE WHEN T.BAIXA = 1 THEN 'PAGO' ELSE 'ABERTO' END) AS status_pagamento
FROM MOB_LISTACONTAS T WHERE T.TIPO = 1 ORDER BY T.ID_CONTA DESC;
