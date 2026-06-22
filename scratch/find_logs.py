import os

log_dir = r"C:\Windows\System32\Logs"
if os.path.exists(log_dir):
    print("Files in System32\\Logs:")
    for f in os.listdir(log_dir):
        print(f" - {f} (size: {os.path.getsize(os.path.join(log_dir, f))})")
else:
    print("System32\\Logs does not exist")
