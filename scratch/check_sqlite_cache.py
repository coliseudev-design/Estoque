import sqlite3

db_path = r"C:\Coliseu\Data\worker.db"
conn = sqlite3.connect(db_path)
cur = conn.cursor()

# Get list of tables
cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
tables = cur.fetchall()
print("Tables in SQLite:")
for t in tables:
    print(f" - {t[0]}")
    # Get schema
    cur.execute(f"PRAGMA table_info({t[0]})")
    cols = cur.fetchall()
    print("   Columns:", [c[1] for c in cols])

# Query some rows from each table
for t in tables:
    cur.execute(f"SELECT COUNT(*) FROM {t[0]}")
    count = cur.fetchone()[0]
    print(f"Table {t[0]} has {count} rows")
    if count > 0:
        cur.execute(f"SELECT * FROM {t[0]} LIMIT 3")
        rows = cur.fetchall()
        print("   Sample rows:")
        for r in rows:
            print(f"     {r}")

conn.close()
