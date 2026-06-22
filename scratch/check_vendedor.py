import fdb

con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey')
cur = con.cursor()
cur.execute("SELECT ID_FUNCIONARIO, NOME, MOB_ACESSO, ID_EMPRESA FROM FUNCIONARIOS WHERE ID_FUNCIONARIO = 105")
row = cur.fetchone()
if row:
    print(f"ID: {row[0]}, NOME: {row[1]}, MOB_ACESSO: {row[2]}, ID_EMPRESA: {row[3]}")
else:
    print("Vendedor 105 not found")
con.close()
