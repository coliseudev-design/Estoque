import sqlite3

db_path = r"c:\Users\rober\.gemini\antigravity\scratch\Coliseu_Sales\Coliseu.Identity\src\Coliseu.Identity.Api\coliseu_identity_dev.db"

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

print("--- ECHO SISTEMAS config in local Identity DB ---")
cursor.execute('SELECT "Id", "Name", "FirebirdHost", "FirebirdDatabasePath", "FirebirdUser", "Status" FROM companies WHERE "Id" = "fb30c585-d3db-4f1d-82ce-01264d2f555a";')
row = cursor.fetchone()
if row:
    print(f"ID: {row[0]}")
    print(f"Name: {row[1]}")
    print(f"Host: {row[2]}")
    print(f"DB Path: {row[3]}")
    print(f"User: {row[4]}")
    print(f"Status: {row[5]}")
else:
    print("Echo Sistemas not found in local db.")

cursor.execute('SELECT "Id", "CompanyId", "Name", "ErpEmpresaId", "IsDefault" FROM branches WHERE "CompanyId" = "fb30c585-d3db-4f1d-82ce-01264d2f555a";')
branches = cursor.fetchall()
print("\nBRANCHES:")
for b in branches:
    print(b)

conn.close()
