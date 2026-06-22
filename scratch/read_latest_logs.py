with open(r"C:\Windows\System32\Logs\worker-20260520.log", "r", encoding="utf-8", errors="ignore") as f:
    lines = f.readlines()

print(f"Total log lines: {len(lines)}")
for line in lines[-20:]:
    print(line.strip())
