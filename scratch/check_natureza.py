import fdb

con = fdb.connect(dsn='C:\\Coliseu\\Data\\PIVETA.FDB', user='sysdba', password='masterkey')
cur = con.cursor()
cur.execute("SELECT ID_NATUREZA, DESCRICAO, OPERACAO, TIPO, PROCESSO FROM NATUREZA_OPERACAO WHERE ID_NATUREZA = 1")
row = cur.fetchone()
if row:
    print(f"ID: {row[0]}, DESCRICAO: {row[1]}, OPERACAO: {row[2]}, TIPO: {row[3]}, PROCESSO: {row[4]}")
else:
    print("Natureza 1 not found")
con.close()

