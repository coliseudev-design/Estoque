using System;
public class Program {
    public static void Main() {
        var str = "
            CREATE OR ALTER PROCEDURE MOB_CADASTRAR_PEDIDO (";
        Console.WriteLine(str.TrimStart().StartsWith("CREATE OR ALTER", StringComparison.OrdinalIgnoreCase));
    }
}
