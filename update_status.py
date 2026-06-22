import fdb
con = fdb.connect(dsn=r"C:\Coliseu\Data\PIVETA.FDB", user="SYSDBA", password="masterkey")
cur = con.cursor()
try:
    cur.execute("UPDATE PEDIDOS SET STATUS = 0 WHERE STATUS = 1 AND PEDIDO LIKE 'MOB%' AND ID_PEDIDO >= 529623")
    con.commit()
    print("Updated to STATUS = 0 successfully")
except Exception as e:
    print(f"Error: {e}")
