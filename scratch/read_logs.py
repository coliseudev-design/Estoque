with open(r"C:\Windows\System32\Logs\worker-20260520.log", "r", encoding="utf-8", errors="ignore") as f:
    lines = f.readlines()
    print("Total lines:", len(lines))
    for line in lines[-200:]:
        print(line.strip())
