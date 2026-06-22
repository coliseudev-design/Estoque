import os

backend_path = r"C:\sistema\backend"
search_term = "internal/sync"
search_term_2 = "/sync"
search_term_3 = "internal"
search_term_4 = "dash_vendas"

for root, dirs, files in os.walk(backend_path):
    if "venv" in root or "__pycache__" in root or ".git" in root:
        continue
    for f in files:
        if f.endswith(".py"):
            full_path = os.path.join(root, f)
            try:
                with open(full_path, "r", encoding="utf-8", errors="ignore") as file:
                    content = file.read()
                    matches = []
                    if search_term in content: matches.append("internal/sync")
                    if search_term_2 in content: matches.append("/sync")
                    if search_term_3 in content: matches.append("internal")
                    if search_term_4 in content: matches.append("dash_vendas")
                    if matches:
                        print(f"Found matches {matches} in {full_path}")
            except Exception as e:
                print(f"Error reading {full_path}: {e}")
