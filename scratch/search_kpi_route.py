import os

search_term = "/kpi"
for root, dirs, files in os.walk(r"c:\Users\rober\.gemini\antigravity\scratch\Coliseu_Sales\middleware\src\routes"):
    for f in files:
        if f.endswith(".js"):
            full_path = os.path.join(root, f)
            try:
                with open(full_path, "r", encoding="utf-8", errors="ignore") as file:
                    content = file.read()
                    if search_term in content:
                        print(f"Found {search_term} in {full_path}")
            except Exception as e:
                pass
