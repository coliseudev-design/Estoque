import sys
sys.stdout.reconfigure(encoding='utf-8')

with open(r"c:\Users\rober\.gemini\antigravity\scratch\Coliseu_Sales\worker\Jobs\SyncCatalogJob.cs", "r", encoding="utf-8") as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if "SyncPerformanceAsync" in line or "PushPerformance" in line:
        print(f"Line {i+1}: {line.strip()}")
        # print 20 lines around
        for j in range(max(0, i-5), min(len(lines), i+35)):
            print(f"  {j+1}: {lines[j].strip()}")
        print("-" * 40)
