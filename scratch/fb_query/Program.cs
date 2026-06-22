using System;
using System.Collections.Generic;
using FirebirdSql.Data.FirebirdClient;
using Npgsql;

class Program
{
    static void Main()
    {
        Console.WriteLine("=== Postgres Branches ===");
        string pgConnString = "Host=localhost;Port=5432;Database=coliseu_sales;Username=postgres;Password=";
        try
        {
            using var pgConn = new NpgsqlConnection(pgConnString);
            pgConn.Open();
            using var pgCmd = pgConn.CreateCommand();
            pgCmd.CommandText = "SELECT \"Id\", \"Name\", \"ErpEmpresaId\", \"ErpDeptoPadrao\", \"CompanyId\" FROM branches";
            using var pgReader = pgCmd.ExecuteReader();
            while (pgReader.Read())
            {
                Console.WriteLine($"ID: {pgReader["Id"]}, Name: {pgReader["Name"]}, ErpEmpresaId: {pgReader["ErpEmpresaId"]}, ErpDeptoPadrao: {pgReader["ErpDeptoPadrao"]}, CompanyId: {pgReader["CompanyId"]}");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error querying Postgres: {ex.Message}");
        }

        string connString = "User=SYSDBA;Password=masterkey;Database=C:\\Coliseu\\Data\\PIVETA.FDB;DataSource=localhost;Port=3050;Dialect=3;Charset=NONE;";
        using var conn = new FbConnection(connString);
        conn.Open();

        Console.WriteLine("\n=== Active Sellers ===");
        using (var cmd = conn.CreateCommand())
        {
            cmd.CommandText = "SELECT ID_FUNCIONARIO, NOME, MOB_ACESSO, ID_EMPRESA FROM FUNCIONARIOS WHERE MOB_ACESSO = 1";
            using var reader = cmd.ExecuteReader();
            while (reader.Read())
            {
                Console.WriteLine($"ID: {reader["ID_FUNCIONARIO"]}, Name: {reader["NOME"]}, Empresa ID: {reader["ID_EMPRESA"]}");
            }
        }

        int sellerId = 105;
        int month = 5;
        int year = 2026;
        string todayStr = "2026-05-20";

        Console.WriteLine($"\n=== Running performance queries for Seller {sellerId} in Month {month}/{year} ===");
        int[] deptos = { 1, 2, 3 };

        foreach (int depto in deptos)
        {
            string sql = $@"
            EXECUTE BLOCK (
                VENDEDOR INTEGER = @VENDEDOR,
                MES INTEGER = @MES,
                ANO INTEGER = @ANO,
                DATA DATE = @DATA,
                EMPRESA INTEGER = @EMPRESA
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
                sum((case when ((ESTOQUE.es = 1) or (ESTOQUE.tipo = 3)) then ESTOQUE.valor_total when ((ESTOQUE.es = 2) and (NATUREZA_OPERACAO.processo = 2)) then (ESTOQUE.valor_total*-1) end))
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
            END";

            using var cmd = conn.CreateCommand();
            cmd.CommandText = sql;
            cmd.Parameters.AddWithValue("@VENDEDOR", sellerId);
            cmd.Parameters.AddWithValue("@MES", month);
            cmd.Parameters.AddWithValue("@ANO", year);
            cmd.Parameters.AddWithValue("@DATA", DateTime.Parse(todayStr));
            cmd.Parameters.AddWithValue("@EMPRESA", depto);

            using var reader = cmd.ExecuteReader();
            if (reader.Read())
            {
                Console.WriteLine($"Depto: {depto}");
                Console.WriteLine($"  Venda Diária: {reader["VENDA_DIARIA"]}");
                Console.WriteLine($"  Venda Mensal: {reader["VENDA_MENSAL"]}");
                Console.WriteLine($"  Comissão Mensal: {reader["COMISSAO_MENSAL"]}");
                Console.WriteLine($"  Meta Mensal: {reader["META_MENSAL"]}");
            }
        }
    }
}
