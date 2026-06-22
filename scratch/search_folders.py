import os

for f in os.listdir("C:\\"):
    path = os.path.join("C:\\", f)
    if os.path.isdir(path):
        print(f"[D] {f}")
    else:
        print(f"[F] {f}")
