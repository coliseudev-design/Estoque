import fdb

def test_conn():
    try:
        conn = fdb.connect(
            dsn=r"C:\Coliseu\Data\PIVETA.FDB",
            user="SYSDBA",
            password="masterkey",
            charset="WIN1252"
        )
        cursor = conn.cursor()
        
        cursor.execute("SELECT FIRST 1 * FROM PRODUTOS p LEFT JOIN CATEGORIAS c ON p.ID_CATEGORIA = c.ID_CATEGORIA WHERE p.TIPO = 2")
        row = cursor.fetchone()
        columns = [desc[0] for desc in cursor.description]
        
        for col, val in zip(columns, row):
            if val is not None and val != 0 and val != '':
                print(f"{col}: {val}")
        
        conn.close()
    except Exception as e:
        print(f"Erro: {e}")

test_conn()
