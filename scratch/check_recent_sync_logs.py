with open(r"C:\Windows\System32\Logs\worker-20260520.log", "r", encoding="utf-8", errors="ignore") as f:
    lines = f.readlines()

print(f"Total log lines: {len(lines)}")
matches = [line.strip() for line in lines if "[Dashboard Sync]" in line]
print(f"Found {len(matches)} [Dashboard Sync] entries. Showing last 30:")
for line in matches[-30:]:
    print(line)
