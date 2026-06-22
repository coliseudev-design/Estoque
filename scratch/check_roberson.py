import fdb

con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey')
cur = con.cursor()
cur.execute("SELECT ID_FUNCIONARIO, NOME, MOB_ACESSO, ID_EMPRESA FROM FUNCIONARIOS WHERE NOME LIKE '%ROBERSON%' OR ID_FUNCIONARIO = 105")
columns = [col[0] for col in cur.description]
rows = cur.fetchall()
for row in rows:
    row_dict = dict(zip(columns, row))
    print(row_dict)
con.close()
