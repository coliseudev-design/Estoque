declare variable ITEM integer;
begin
    select coalesce(max(id_item),0)+1 from PEDIDO_ITENS where id_pedido = :ID_PEDIDO into :ITEM;

    insert into PEDIDO_ITENS (ID_PEDIDO, ID_ITEM, ID_PRODUTO, DESCRICAO, UNIDADE, QTDE, VALOR_UNITARIO, CF, VALOR_TOTAL, VALOR_FINAL, VALOR_FINAL_UN,
                              TIPO, VALOR_CUSTO, CODIGO_BARRA, TIPO_UNIDADE, DESCONTO, STATUS, ICMS, REDUCAO_ICMS, TRIBUTACAO,
                              BASE_CALCULO, VALOR_ICMS, BASE_ICMS_SUB, VALOR_ICMS_SUB, PESO, CFOP, PIS_CST, COFINS_CST, IPI_CST, PIS, COFINS, IPI, CSOSN,
                              ORIGEM, LUCRO, LUCRO_MAX, ENTREGAR, VALOR_IPI, BASE_IPI, BASE_PIS, BASE_COFINS)
                              values ( :ID_PEDIDO, :ITEM, :PRODUTO,
                              (select descricao from produtos where ID_PRODUTO = :PRODUTO),
                              (select unidade from produtos where ID_PRODUTO = :PRODUTO),
                              :QUANTIDADE, :VALOR_UNITARIO,
                              (select ORIGEM_MERCADORIA || TRIBUTACAO from produtos where ID_PRODUTO = :PRODUTO),
                              :VALOR_TOTAL, :VALOR_TOTAL, :VALOR_UNITARIO, 1,
                              (select PRODUTO_PRECOS.PRECO_CUSTO from produtos, produto_precos where (produtos.id_produto = produto_precos.id_produto) and (produto_precos.ativo = 1) and (produtos.ID_PRODUTO = :PRODUTO)),
                              (select codigo_barra from produtos where ID_PRODUTO = :PRODUTO), 1,
                              (select desconto from pedidos where id_pedido = :ID_PEDIDO), 1,
                              (select icms from produtos where ID_PRODUTO = :PRODUTO),
                              (select reducao from produtos where ID_PRODUTO = :PRODUTO),
                              (select tributacao from produtos where ID_PRODUTO = :PRODUTO),
                              0,
                              0,
                              0,
                              0,
                              (select peso from produtos where ID_PRODUTO = :PRODUTO), (select cfop_e from produtos where ID_PRODUTO = :PRODUTO),
                              (select pis_cst from produtos where ID_PRODUTO = :PRODUTO),
                              (select cofins_cst from produtos where ID_PRODUTO = :PRODUTO),
                              (select ipi_cst from produtos where ID_PRODUTO = :PRODUTO),
                              (select pis from produtos where ID_PRODUTO = :PRODUTO),
                              (select cofins from produtos where ID_PRODUTO = :PRODUTO),
                              (select ipi from produtos where ID_PRODUTO = :PRODUTO),
                              (select csosn from produtos where ID_PRODUTO = :PRODUTO),
                              (select origem_mercadoria from produtos where ID_PRODUTO = :PRODUTO),
                              (select margem_lucro from produtos where ID_PRODUTO = :PRODUTO),
                              (select margem_maxima from produtos where ID_PRODUTO = :PRODUTO), 0,
                              0,
                              0,
                              0,
                              0);


    update PEDIDOS set
    peso_total = (select sum(peso) from pedido_itens where id_pedido = :ID_PEDIDO)
    where id_pedido = :ID_PEDIDO;

end