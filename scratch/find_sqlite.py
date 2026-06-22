import os

search_paths = [
    r"C:\Sales",
    r"C:\Coliseu",
    r"c:\Users\rober\.gemini\antigravity\scratch\Coliseu_Sales"
]

print("Searching for sync_cache.sqlite...")
for path in search_paths:
    if os.path.exists(path):
        for root, dirs, files in os.walk(path):
            if "sync_cache.sqlite" in files:
                full_path = os.path.join(root, "sync_cache.sqlite")
                print(f"Found: {full_path} (size: {os.path.getsize(full_path)} bytes)")
