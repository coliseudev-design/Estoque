using System;
using FirebirdSql.Data.FirebirdClient;

class Program
{
    static void Main()
    {
        string connStr = "User=SYSDBA;Password=masterkey;Database=C:\\Coliseu\\Data\\PIVETA.FDB;DataSource=localhost;Port=3050;Dialect=3;Charset=NONE;Role=;Connection lifetime=15;Pooling=true;MinPoolSize=0;MaxPoolSize=50;Packet Size=8192;ServerType=0;";
        using (var conn = new FbConnection(connStr))
        {
            conn.Open();
            try {
                using (var cmd = new FbCommand("SELECT FIRST 1 p.N_PEDIDO FROM PEDIDOS p", conn)) {
                    cmd.ExecuteNonQuery();
                    Console.WriteLine("N_PEDIDO EXISTS!");
                }
            } catch (Exception ex) { Console.WriteLine("N_PEDIDO Error: " + ex.Message); }

            try {
                using (var cmd = new FbCommand("SELECT FIRST 1 i.VALOR_FINAL_UN FROM PEDIDO_ITENS i", conn)) {
                    cmd.ExecuteNonQuery();
                    Console.WriteLine("VALOR_FINAL_UN EXISTS!");
                }
            } catch (Exception ex) { Console.WriteLine("VALOR_FINAL_UN Error: " + ex.Message); }
            
            try {
                using (var cmd = new FbCommand("SELECT FIRST 1 f.CNPJ, f.TELEFONE FROM FORNECEDORES f", conn)) {
                    cmd.ExecuteNonQuery();
                    Console.WriteLine("FORNECEDORES EXISTS!");
                }
            } catch (Exception ex) { Console.WriteLine("FORNECEDORES Error: " + ex.Message); }
        }
    }
}
