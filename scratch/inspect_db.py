import sqlite3
import os

db_paths = [
    "mobile/sqlite.db",
    os.path.expandvars(r"%LOCALAPPDATA%\Google\AndroidStudio2026.1\device-explorer\...") # or emulator path
]

# Let's search for sqlite.db in the directory first
print("Searching for sqlite.db...")
for root, dirs, files in os.walk("."):
    for f in files:
        if f.endswith(".db") or f == "sqlite":
            print(f"Found database file: {os.path.join(root, f)}")

db_file = "mobile/sqlite.db"
if os.path.exists(db_file):
    print(f"\nInspecting {db_file}:")
    try:
        conn = sqlite3.connect(db_file)
        cursor = conn.cursor()
        
        # Get tables
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
        tables = [r[0] for r in cursor.fetchall()]
        print(f"Tables: {tables}")
        
        for table in ['seller_kpis', 'erp_sales_rankings', 'branches', 'orders']:
            if table in tables:
                cursor.execute(f"SELECT COUNT(*) FROM {table}")
                count = cursor.fetchone()[0]
                print(f"Table '{table}' has {count} rows.")
                if count > 0:
                    cursor.execute(f"SELECT * FROM {table} LIMIT 5")
                    print(f"Sample rows from {table}:")
                    for row in cursor.fetchall():
                        print(row)
        conn.close()
    except Exception as e:
        print(f"Error reading DB: {e}")
else:
    print(f"{db_file} does not exist.")
