import sqlite3

def main():
    conn = sqlite3.connect('mobile/sqlite.db')
    cursor = conn.cursor()
    
    # List tables
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
    tables = [t[0] for t in cursor.fetchall()]
    print("Tables:", tables)
    
    for table in tables:
        try:
            cursor.execute(f"SELECT COUNT(*) FROM {table}")
            count = cursor.fetchone()[0]
            print(f"Table {table}: {count} rows")
        except Exception as e:
            print(f"Error counting table {table}: {e}")

    # Inspect seller_kpis
    if 'seller_kpis' in tables:
        cursor.execute("SELECT * FROM seller_kpis")
        rows = cursor.fetchall()
        print("\nRows in seller_kpis:")
        for r in rows:
            print(r)

    # Inspect settings/config
    # Look for tables that might hold app config
    config_tables = [t for t in tables if 'config' in t or 'setting' in t or 'session' in t]
    for ct in config_tables:
        try:
            cursor.execute(f"SELECT * FROM {ct} LIMIT 10")
            print(f"\nRows in {ct}:")
            for r in cursor.fetchall():
                print(r)
        except Exception as e:
            print(e)

if __name__ == '__main__':
    main()
