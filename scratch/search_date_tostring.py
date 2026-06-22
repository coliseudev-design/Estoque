import os

for root, dirs, files in os.walk(r"c:\Users\rober\.gemini\antigravity\scratch\Coliseu_Sales\worker\Jobs"):
    for f in files:
        if f.endswith(".cs"):
            full_path = os.path.join(root, f)
            with open(full_path, "r", encoding="utf-8", errors="ignore") as file:
                for i, line in enumerate(file):
                    if "ToString" in line and any(x in line.lower() for x in ["data", "dia", "date", "emissao", "created"]):
                        print(f"{f}:{i+1}: {line.strip()}")
