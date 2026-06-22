import fdb

con = fdb.connect(dsn=r"C:\Coliseu\Data\PIVETA.FDB", user="SYSDBA", password="masterkey")
cur = con.cursor()

def compare_pedidos(id_mob, id_erp):
    cur.execute("SELECT * FROM PEDIDOS WHERE ID_PEDIDO = ?", (id_mob,))
    cols = [desc[0] for desc in cur.description]
    row_mob = cur.fetchone()
    
    cur.execute("SELECT * FROM PEDIDOS WHERE ID_PEDIDO = ?", (id_erp,))
    row_erp = cur.fetchone()
    
    print(f"{'COLUMN':<25} | {'MOBILE (529699)':<25} | {'ERP (529674)':<25}")
    print("-" * 80)
    for col, val_mob, val_erp in zip(cols, row_mob, row_erp):
        if val_mob != val_erp:
            print(f"{col:<25} | {str(val_mob):<25} | {str(val_erp):<25}")

compare_pedidos(529699, 529674)
