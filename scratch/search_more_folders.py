import os

def check_dir(path):
    if os.path.exists(path):
        print(f"--- {path} ---")
        try:
            for f in os.listdir(path):
                print(f"  {f}")
        except Exception as e:
            print(f"  Error: {e}")

check_dir("C:\\var")
check_dir("C:\\SITES")
check_dir("C:\\sistema")
check_dir("C:\\Sales")
