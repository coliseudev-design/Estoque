import fdb
conn = fdb.connect(dsn=r'C:\Coliseu\Data\PIVETA.FDB', user='SYSDBA', password='masterkey')
c = conn.cursor()

for table in ['PRODUTO_DEPTOS', 'PRODUTO_ITENS_DEPTOS']:
    print(f"\n--- Columns in {table} ---")
    try:
        c.execute(f"SELECT FIRST 1 * FROM {table}")
        row = c.fetchone()
        columns = [desc[0] for desc in c.description]
        if row:
            for col, val in zip(columns, row):
                print(f"{col}: {val}")
        else:
            print("Table is empty. Columns:")
            print(columns)
    except Exception as e:
        print(f"Error reading {table}: {e}")

conn.close()
