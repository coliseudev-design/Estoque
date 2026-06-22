import sqlite3

db_path = r"C:\Sales\sync_cache.sqlite"
conn = sqlite3.connect(db_path)
cur = conn.cursor()

ids = [529692, 529693, 529694, 529695, 529696, 529697]
print("Checking Dash_Vendas hashes in SQLite:")
for i in ids:
    cur.execute("SELECT RowHash, SyncedAt FROM SyncHashes WHERE Entity = 'Dash_Vendas' AND IdFirebird = ?", (str(i),))
    row = cur.fetchone()
    if row:
        print(f"Order: {i}, Hash: {row[0]}, SyncedAt: {row[1]}")
    else:
        print(f"Order: {i} not found in SyncHashes")

conn.close()
