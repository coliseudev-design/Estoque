import sqlite3

db_path = r"C:\Sales\sync_cache.sqlite"
conn = sqlite3.connect(db_path)
cur = conn.cursor()

cur.execute("SELECT Entity, COUNT(*) FROM SyncHashes GROUP BY Entity")
rows = cur.fetchall()
print("Entity counts in SyncHashes:")
for r in rows:
    print(f" - {r[0]}: {r[1]} hashes")

conn.close()
