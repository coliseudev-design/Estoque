import os

def check_dir(path):
    if os.path.exists(path):
        try:
            print(f"Contents of {path}:")
            for f in os.listdir(path):
                full = os.path.join(path, f)
                if os.path.isdir(full):
                    print(f"  [D] {f}")
                else:
                    print(f"  [F] {f}")
        except Exception as e:
            print(f"Error reading {path}: {e}")
    else:
        print(f"{path} does not exist")

check_dir(r"C:\Users\rober")
