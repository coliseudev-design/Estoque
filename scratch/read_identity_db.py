import sqlite3
import json

db_path = "Coliseu.Identity/ColiseuIdentity.db"

def inspect_db():
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # List tables
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
    tables = [r[0] for r in cursor.fetchall()]
    print("Tables in database:", tables)
    
    for table in tables:
        print(f"\n--- Table: {table} ---")
        try:
            cursor.execute(f"PRAGMA table_info({table})")
            columns = [c[1] for c in cursor.fetchall()]
            print("Columns:", columns)
            
            cursor.execute(f"SELECT * FROM {table} LIMIT 10")
            rows = cursor.fetchall()
            print(f"Rows ({len(rows)}):")
            for r in rows:
                print(r)
        except Exception as e:
            print("Error reading table:", e)
            
    conn.close()

if __name__ == "__main__":
    inspect_db()
