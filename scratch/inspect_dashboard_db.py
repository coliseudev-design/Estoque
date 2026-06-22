import sqlite3

db_path = "C:\\sistema\\backend\\dashboard.db"
conn = sqlite3.connect(db_path)
cur = conn.cursor()

# Check tables
cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
tables = [t[0] for t in cur.fetchall()]
print("Tables in dashboard.db:", tables)

# Get row count for each table
for table in tables:
    try:
        cur.execute(f"SELECT COUNT(*) FROM {table}")
        count = cur.fetchone()[0]
        print(f"Table '{table}': {count} rows")
    except Exception as e:
        print(f"Table '{table}': Error: {e}")

conn.close()
