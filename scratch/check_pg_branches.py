import psycopg2
import os

pg_host = os.getenv('PG_HOST', 'localhost')
pg_port = os.getenv('PG_PORT', '5432')
pg_database = os.getenv('PG_DATABASE', 'coliseu_sales')
pg_user = os.getenv('PG_USER', 'postgres')
pg_password = os.getenv('PG_PASSWORD', '')

try:
    conn = psycopg2.connect(
        host=pg_host,
        port=pg_port,
        database=pg_database,
        user=pg_user,
        password=pg_password
    )
    c = conn.cursor()
    c.execute('SELECT "Id", "Name", "ErpEmpresaId", "ErpDeptoPadrao", "IsDefault" FROM branches')
    print("BRANCHES IN PG:")
    for row in c.fetchall():
        print(f"Id: {row[0]}, Name: {row[1]}, ErpEmpresaId: {row[2]}, ErpDeptoPadrao: {row[3]}, IsDefault: {row[4]}")
    conn.close()
except Exception as e:
    print("Error connecting to PG:", e)
