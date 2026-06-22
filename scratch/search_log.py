import sys
sys.stdout.reconfigure(encoding='utf-8')

log_path = r"C:\Windows\System32\Logs\worker-20260521.log"
matches = []

with open(log_path, "r", encoding="utf-8", errors="ignore") as f:
    for line in f:
        if "Performance" in line or "performance" in line:
            matches.append(line.strip())

print(f"Total matching lines: {len(matches)}")
print("Last 30 matches:")
for m in matches[-30:]:
    print(m)
