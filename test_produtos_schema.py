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
        
        cursor.execute("SELECT FIRST 1 * FROM PRODUTOS")
        columns = [desc[0] for desc in cursor.description]
        print("Colunas de PRODUTOS:")
        print(", ".join(columns))
        
        conn.close()
    except Exception as e:
        print(f"Erro: {e}")

test_conn()
