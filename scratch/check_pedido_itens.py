import fdb

con = fdb.connect(dsn=r"C:\Coliseu\Data\PIVETA.FDB", user="SYSDBA", password="masterkey")
cur = con.cursor()

def check_itens(id_pedido):
    print(f"\n=== ITENS DO PEDIDO {id_pedido} ===")
    cur.execute("SELECT * FROM PEDIDO_ITENS WHERE ID_PEDIDO = ?", (id_pedido,))
    col_names = [desc[0] for desc in cur.description]
    rows = cur.fetchall()
    for row in rows:
        for col, val in zip(col_names, row):
            if val is not None:
                print(f"  {col}: {val}")
        print("-" * 30)

check_itens(529699)
check_itens(529674)
