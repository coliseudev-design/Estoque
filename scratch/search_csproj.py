import os

for root, dirs, files in os.walk(r"c:\Users\rober\.gemini\antigravity\scratch\Coliseu_Sales"):
    for f in files:
        if f.endswith(".csproj"):
            print(os.path.join(root, f))
