import sys
sys.stdout.reconfigure(encoding='utf-8')

with open(r"c:\Users\rober\.gemini\antigravity\scratch\Coliseu_Sales\worker\Jobs\SyncDashboardDataJob.cs", "r", encoding="utf-8") as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if "ToString" in line:
        print(f"Line {i+1}: {line.strip()}")
