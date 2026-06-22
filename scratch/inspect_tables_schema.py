import sys
sys.stdout.reconfigure(encoding='utf-8')
import fdb

conn = fdb.connect(dsn=r'C:\Coliseu\Data\PIVETA.FDB', user='SYSDBA', password='masterkey', charset='WIN1252')
cur = conn.cursor()

def run_query(title, query):
    print(f"=== {title} ===")
    try:
        cur.execute(query)
        desc = [col[0] for col in cur.description]
        print(" | ".join(desc))
        print("-" * 50)
        rows = cur.fetchall()
        for row in rows:
            print(" | ".join(str(val).strip() if val is not None else "NULL" for val in row))
    except Exception as e:
        print(f"Error: {e}")
    print()

run_query("DEPARTAMENTOS", "SELECT ID_DEPTO, DESCRICAO, OP_ESTOQUE FROM DEPARTAMENTOS")
run_query("EMPRESA", "SELECT ID_EMPRESA, RAZAO_SOCIAL, CNPJ FROM EMPRESA")
run_query("CONFIG", "SELECT ID_EMPRESA, DEPTO_PADRAO FROM CONFIG")

conn.close()
