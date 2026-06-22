import sqlite3

db_path = "C:\\Sales\\sync_cache.sqlite"
conn = sqlite3.connect(db_path)
cur = conn.cursor()

# Check if tables exist
cur.execute("SELECT name FROM sqlite_master WHERE type='table'")
print("Tables:", cur.fetchall())

# Check recent entries in SyncHashes
cur.execute("SELECT Entity, IdFirebird, RowHash, SyncedAt FROM SyncHashes WHERE IdFirebird IN ('529692', '529693', '529694', '529695')")
rows = cur.fetchall()
print("SyncHashes for target orders:")
for r in rows:
    print(r)

# Also check last 10 synced orders
cur.execute("SELECT Entity, IdFirebird, RowHash, SyncedAt FROM SyncHashes WHERE Entity = 'Dash_Vendas' ORDER BY SyncedAt DESC LIMIT 10")
print("\nLast 10 synced Dash_Vendas:")
for r in cur.fetchall():
    print(r)

conn.close()
