with open("worker_restart2.log", "r", encoding="utf-8", errors="ignore") as f:
    lines = f.readlines()

print(f"Total lines: {len(lines)}")
for line in lines[-100:]:
    print(line.strip())
