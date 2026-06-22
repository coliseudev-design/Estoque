with open("worker_restart2.log", "r", encoding="utf-8", errors="ignore") as f:
    lines = f.readlines()

print(f"Total lines: {len(lines)}")

count = 0
for idx, line in enumerate(lines):
    if "performance" in line.lower() or "error" in line.lower() or "exception" in line.lower() or "fail" in line.lower():
        print(f"L{idx}: {line.strip()}")
        count += 1
        if count > 50:
            print("Truncated after 50 matches")
            break
