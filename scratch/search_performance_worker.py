import os

search_term = "SyncPerformance"
search_term_2 = "performance"

for root, dirs, files in os.walk(r"c:\Users\rober\.gemini\antigravity\scratch\Coliseu_Sales\worker"):
    for f in files:
        if f.endswith(".cs"):
            full_path = os.path.join(root, f)
            try:
                with open(full_path, "r", encoding="utf-8", errors="ignore") as file:
                    content = file.read()
                    if search_term in content or search_term_2 in content:
                        print(f"Found match in {full_path}")
            except Exception as e:
                pass
