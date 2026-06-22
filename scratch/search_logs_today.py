import re

log_path = r"C:\Windows\System32\Logs\worker-20260520.log"
pattern = re.compile(r"Dash_Vendas|dash_vendas", re.IGNORECASE)

matches = []
with open(log_path, "r", encoding="utf-8", errors="ignore") as f:
    for line in f:
        if pattern.search(line):
            matches.append(line.strip())

print(f"Found {len(matches)} matching log lines for today.")
print("Last 30 matches:")
for m in matches[-30:]:
    print(m)
