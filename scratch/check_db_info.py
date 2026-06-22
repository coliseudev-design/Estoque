import fdb

con = fdb.connect(dsn=r"C:\Coliseu\Data\PIVETA.FDB", user="SYSDBA", password="masterkey")
cur = con.cursor()

def save_sp(sp_name, filename):
    cur.execute("SELECT RDB$PROCEDURE_SOURCE FROM RDB$PROCEDURES WHERE TRIM(RDB$PROCEDURE_NAME) = ?", (sp_name,))
    row = cur.fetchone()
    if row and row[0]:
        with open(filename, "w", encoding="utf-8") as f:
            f.write(row[0])
        print(f"Saved {sp_name} to {filename}")
    else:
        print(f"Stored Procedure {sp_name} not found")

save_sp("MOB_CADASTRAR_PEDIDO", "scratch/mob_cadastrar_pedido.sql")
save_sp("MOB_CADASTRAR_PEDIDO_ITEM", "scratch/mob_cadastrar_pedido_item.sql")
