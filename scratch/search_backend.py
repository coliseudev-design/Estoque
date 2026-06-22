import os

backend_path = r"C:\sistema\backend"
search_term = "dash_vendas"

for root, dirs, files in os.walk(backend_path):
    for f in files:
        if f.endswith(".py"):
            full_path = os.path.join(root, f)
            try:
                with open(full_path, "r", encoding="utf-8", errors="ignore") as file:
                    content = file.read()
                    if search_term in content:
                        print(f"Found '{search_term}' in {full_path}")
            except Exception as e:
                print(f"Error reading {full_path}: {e}")
