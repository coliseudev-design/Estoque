import sqlite3
import os

db_path = r"c:\Users\rober\.gemini\antigravity\scratch\Coliseu_Sales\Coliseu.Identity\src\Coliseu.Identity.Api\coliseu_identity_dev.db"

if not os.path.exists(db_path):
    print(f"Db path not found: {db_path}")
    exit(1)

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

print("TABLES:")
cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
tables = cursor.fetchall()
for t in tables:
    print(t[0])

print("\nCOMPANIES:")
try:
    cursor.execute('SELECT "Id", "Name", "Cnpj" FROM companies;')
    for row in cursor.fetchall():
        print(row)
except Exception as e:
    print(f"Error reading companies: {e}")

print("\nBRANCHES:")
try:
    cursor.execute('SELECT "Id", "CompanyId", "Name", "ErpEmpresaId", "ErpDeptoPadrao", "IsDefault" FROM branches;')
    for row in cursor.fetchall():
        print(row)
except Exception as e:
    print(f"Error reading branches: {e}")

conn.close()
