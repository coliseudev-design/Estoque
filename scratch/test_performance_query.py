import fdb
from datetime import date

con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey', charset='WIN1252')
cur = con.cursor()

sellerId = 105
month = 5
year = 2026
today = date.today().strftime('%Y-%m-%d')
firstDay = '2026-05-01'
lastDay = '2026-05-31'
empresaId = 1
deptoId = 1

mobMinhasVendasSql = """
EXECUTE BLOCK (
    VENDEDOR INTEGER = ?,
    MES INTEGER = ?,
    ANO INTEGER = ?,
    DATA DATE = ?,
    EMPRESA INTEGER = ?
)
RETURNS (
    VENDA_DIARIA NUMERIC(15,2), VENDA_MENSAL NUMERIC(15,2),
    COMISSAO_DIARIA NUMERIC(15,2), COMISSAO_MENSAL NUMERIC(15,2),
    META_DIARIA NUMERIC(15,2), META_MENSAL NUMERIC(15,2),
    SERVICO_MENSAL NUMERIC(15,2), COMISSAO_SV_MENSAL NUMERIC(15,2)
)
AS
declare variable MT_D numeric(15,2); declare variable MT_M numeric(15,2);
declare variable VEND_D numeric(15,2); declare variable VEND_M numeric(15,2);
declare variable COM_D numeric(15,2); declare variable COM_M numeric(15,2);
declare variable SERV_M numeric(15,2); declare variable COM_SV_M numeric(15,2);
BEGIN
    select FUNCIONARIOS.META_DIARIA, FUNCIONARIOS.META_MENSAL,
    sum((case when ((ESTOQUE.es = 1) or (ESTOQUE.tipo = 3)) then ESTOQUE.valor_total when ((ESTOQUE.es = 2) and (NATUREZA_OPERACAO.processo = 2)) then (ESTOQUE.valor_total*-1) end) - (((case when ((ESTOQUE.es = 1) or (ESTOQUE.tipo = 3)) then ESTOQUE.valor_total when ((ESTOQUE.es = 2) and (NATUREZA_OPERACAO.processo = 2)) then (ESTOQUE.valor_total*-1) end)*PEDIDOS.desconto)/100)),
    sum((case when ((ESTOQUE.es = 1) or (ESTOQUE.tipo = 3)) then ESTOQUE.valor_comissao when ((ESTOQUE.es = 2) and (NATUREZA_OPERACAO.processo = 2)) then (ESTOQUE.valor_comissao*-1) end))
    from ESTOQUE inner join PEDIDOS on (PEDIDOS.ID_PEDIDO = ESTOQUE.ID_PEDIDO)
    left join FUNCIONARIOS on (FUNCIONARIOS.ID_FUNCIONARIO = PEDIDOS.id_vendedor)
    left join natureza_operacao on (natureza_operacao.id_natureza = pedidos.id_natureza)
    where (natureza_operacao.calc_comissao = 1) and (extract(month from PEDIDOS.data_vencimento) = :MES) and (extract(year from PEDIDOS.data_vencimento) = :ANO)
    and (PEDIDOS.ID_VENDEDOR = :VENDEDOR) and (PEDIDOS.ID_DEPTO = :EMPRESA) and (PEDIDOS.TIPO = 1) and (PEDIDOS.STATUS = 2) and (ESTOQUE.STATUS <> 9) and (ESTOQUE.movc = 1)
    group by FUNCIONARIOS.META_DIARIA, FUNCIONARIOS.META_MENSAL into :MT_D, :MT_M, :VEND_M, :COM_M;

    select sum((case when ((ESTOQUE.es = 1) or (ESTOQUE.tipo = 3)) then ESTOQUE.valor_total when ((ESTOQUE.es = 2) and (NATUREZA_OPERACAO.processo = 2)) then (ESTOQUE.valor_total*-1) end) - (((case when ((ESTOQUE.es = 1) or (ESTOQUE.tipo = 3)) then ESTOQUE.valor_total when ((ESTOQUE.es = 2) and (NATUREZA_OPERACAO.processo = 2)) then (ESTOQUE.valor_total*-1) end)*PEDIDOS.desconto)/100)),
    sum((case when ((ESTOQUE.es = 1) or (ESTOQUE.tipo = 3)) then ESTOQUE.valor_comissao when ((ESTOQUE.es = 2) and (NATUREZA_OPERACAO.processo = 2)) then (ESTOQUE.valor_comissao*-1) end))
    from ESTOQUE inner join PEDIDOS on (PEDIDOS.ID_PEDIDO = ESTOQUE.ID_PEDIDO) left join FUNCIONARIOS on (FUNCIONARIOS.ID_FUNCIONARIO = PEDIDOS.id_vendedor)
    left join natureza_operacao on (natureza_operacao.id_natureza = pedidos.id_natureza)
    where (natureza_operacao.calc_comissao = 1) and ((PEDIDOS.data_vencimento >= :DATA) and (PEDIDOS.data_vencimento <= :DATA))
    and (PEDIDOS.ID_VENDEDOR = :VENDEDOR) and (PEDIDOS.ID_DEPTO = :EMPRESA) and (PEDIDOS.TIPO = 1) and (PEDIDOS.STATUS = 2) and (ESTOQUE.STATUS <> 9) and (ESTOQUE.movc = 1)
    into :VEND_D, :COM_D;

    select sum(LISTAPEDIDOS_ITENS.VALOR_TOTAL), sum(((LISTAPEDIDOS_ITENS.VALOR_TOTAL*(case when PRODUTOS.forca_comissao = 1 then PRODUTOS.comissao else FUNCIONARIOS.comissao end))/100))
    from LISTAPEDIDOS_ITENS left join PRODUTOS on (PRODUTOS.ID_PRODUTO = LISTAPEDIDOS_ITENS.ID_PRODUTO)
    left join FUNCIONARIOS on (FUNCIONARIOS.ID_FUNCIONARIO = LISTAPEDIDOS_ITENS.id_tecnico) left join NATUREZA_OPERACAO on (natureza_operacao.id_natureza = LISTAPEDIDOS_ITENS.id_natureza)
    where (natureza_operacao.calc_comissao = 1) and ((LISTAPEDIDOS_ITENS.tipo_item = 3) or (LISTAPEDIDOS_ITENS.tipo_item = 6)) and (extract(month from LISTAPEDIDOS_ITENS.data_vencimento) = :MES) and (extract(year from LISTAPEDIDOS_ITENS.data_vencimento) = :ANO)
    and (LISTAPEDIDOS_ITENS.id_tecnico = :VENDEDOR) and (LISTAPEDIDOS_ITENS.ID_DEPTO = :EMPRESA) and (LISTAPEDIDOS_ITENS.TIPO = 1) and (LISTAPEDIDOS_ITENS.STATUS = 2)
    into :SERV_M, :COM_SV_M;

    VENDA_DIARIA = coalesce(:VEND_D, 0); VENDA_MENSAL = coalesce(:VEND_M, 0);
    COMISSAO_DIARIA = coalesce(:COM_D, 0); COMISSAO_MENSAL = coalesce(:COM_M, 0);
    META_DIARIA = coalesce(:MT_D, 0); META_MENSAL = coalesce(:MT_M, 0);
    SERVICO_MENSAL = coalesce(:SERV_M, 0); COMISSAO_SV_MENSAL = coalesce(:COM_SV_M, 0);
    SUSPEND;
END
"""

print("Executing mobMinhasVendasSql...")
cur.execute(mobMinhasVendasSql, (sellerId, month, year, today, deptoId))
row = cur.fetchone()
if row:
    cols = ['VENDA_DIARIA', 'VENDA_MENSAL', 'COMISSAO_DIARIA', 'COMISSAO_MENSAL', 'META_DIARIA', 'META_MENSAL', 'SERVICO_MENSAL', 'COMISSAO_SV_MENSAL']
    for col, val in zip(cols, row):
        print(f"  {col}: {val}")

mobMinhasVendasRSql = """
EXECUTE BLOCK (
    VENDEDOR INTEGER = ?,
    DATAI DATE = ?,
    DATAF DATE = ?,
    DIA DATE = ?,
    EMPRESA INTEGER = ?,
    DEPTO INTEGER = ?
)
RETURNS (
    TOTAL_DIARIO NUMERIC(15,2), TOTAL_MENSAL NUMERIC(15,2),
    COMISSAO_DIARIA NUMERIC(15,2), COMISSAO_MENSAL NUMERIC(15,2)
)
AS
declare variable COM_D decimal(15,2); declare variable COM_M decimal(15,2);
declare variable TOT_V_D decimal(15,2); declare variable TOT_V_M decimal(15,2);
declare variable TP_COM smallint;
BEGIN
    select COMISSAO_TIPO from config where ID_EMPRESA = :EMPRESA into :TP_COM;
    if (TP_COM = 1) then BEGIN
        Select SUM(VALOR_PAGO), SUM(COMISSAO_PAGAR) from REL_IC_COMISSAO2 WHERE ((DATA_PAGAMENTO >= :DATAI) AND (DATA_PAGAMENTO <= :DATAF)) AND (ID_VENDEDOR = :VENDEDOR) AND (ID_DEPTO = :DEPTO) into :TOT_V_M, :COM_M;
        Select SUM(VALOR_PAGO), SUM(COMISSAO_PAGAR) from REL_IC_COMISSAO2 WHERE (DATA_PAGAMENTO = :DIA) AND (ID_VENDEDOR = :VENDEDOR) AND (ID_DEPTO = :DEPTO) into :TOT_V_D, :COM_D;
    END
    if (TP_COM = 2) then BEGIN
        Select SUM(VALOR_PAGO), SUM(COMISSAO_PAGAR) from REL_IC_COMISSAO_ITEM2 WHERE ((DATA_PAGAMENTO >= :DATAI) AND (DATA_PAGAMENTO <= :DATAF)) AND (ID_VENDEDOR = :VENDEDOR) AND (ID_DEPTO = :DEPTO) into :TOT_V_M, :COM_M;
        Select SUM(VALOR_PAGO), SUM(COMISSAO_PAGAR) from REL_IC_COMISSAO_ITEM2 WHERE (DATA_PAGAMENTO = :DIA) AND (ID_VENDEDOR = :VENDEDOR) AND (ID_DEPTO = :DEPTO) into :TOT_V_D, :COM_D;
    END
    if (TP_COM = 3) then BEGIN
        Select SUM(VALOR_PAGO), SUM(COMISSAO_PAGAR) from REL_IC_COMISSAO_VAR2 WHERE ((DATA_PAGAMENTO >= :DATAI) AND (DATA_PAGAMENTO <= :DATAF)) AND (ID_VENDEDOR = :VENDEDOR) AND (ID_DEPTO = :DEPTO) into :TOT_V_M, :COM_M;
        Select SUM(VALOR_PAGO), SUM(COMISSAO_PAGAR) from REL_IC_COMISSAO_VAR2 WHERE (DATA_PAGAMENTO = :DIA) AND (ID_VENDEDOR = :VENDEDOR) AND (ID_DEPTO = :DEPTO) into :TOT_V_D, :COM_D;
    END
    COMISSAO_DIARIA = coalesce(:COM_D, 0); COMISSAO_MENSAL = coalesce(:COM_M, 0);
    TOTAL_DIARIO = coalesce(:TOT_V_D, 0); TOTAL_MENSAL = coalesce(:TOT_V_M, 0);
    SUSPEND;
END
"""

print("\nExecuting mobMinhasVendasRSql...")
cur.execute(mobMinhasVendasRSql, (sellerId, firstDay, lastDay, today, empresaId, deptoId))
row = cur.fetchone()
if row:
    cols = ['TOTAL_DIARIO', 'TOTAL_MENSAL', 'COMISSAO_DIARIA', 'COMISSAO_MENSAL']
    for col, val in zip(cols, row):
        print(f"  {col}: {val}")

con.close()
