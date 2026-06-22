import os

search_term = "admin-api-key"
for root, dirs, files in os.walk("."):
    if "node_modules" in root or "venv" in root or ".git" in root or ".idea" in root:
        continue
    for f in files:
        if f.endswith((".js", ".json", ".py", ".cs", ".yml", ".conf", ".sh", ".bat")):
            full_path = os.path.join(root, f)
            try:
                with open(full_path, "r", encoding="utf-8", errors="ignore") as file:
                    content = file.read()
                    if search_term in content.lower():
                        print(f"Found {search_term} in {full_path}")
            except Exception as e:
                pass
