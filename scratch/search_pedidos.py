with open(r"C:\sistema\backend\routers\pedidos.py", "r", encoding="utf-8", errors="ignore") as f:
    for i, line in enumerate(f, 1):
        if "sync" in line.lower() or "dash" in line.lower() or "venda" in line.lower():
            print(f"{i}: {line.strip()}")
