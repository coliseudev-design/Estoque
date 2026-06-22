import sys
sys.stdout.reconfigure(encoding='utf-8')
with open("build_configurator.log", "r", encoding="utf-16") as f:
    print(f.read()[:2000])
