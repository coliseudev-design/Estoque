import sys

# Set standard output encoding to utf-8 if possible
try:
    sys.stdout.reconfigure(encoding='utf-8')
except AttributeError:
    pass

with open(r"C:\Windows\System32\Logs\worker-20260520.log", "r", encoding="utf-8", errors="ignore") as f:
    for line in f:
        if "[Dashboard Sync]" in line or "Dash_Vendas" in line:
            # print cleanly
            print(line.strip().encode('ascii', 'replace').decode('ascii'))
