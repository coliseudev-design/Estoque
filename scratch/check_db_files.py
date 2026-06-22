import os
import datetime

path1 = r"C:\Coliseu\PIVETA.FDB"
path2 = r"C:\Coliseu\Data\PIVETA.FDB"

for p in [path1, path2]:
    if os.path.exists(p):
        mtime = os.path.getmtime(p)
        dt = datetime.datetime.fromtimestamp(mtime)
        print(f"File: {p}")
        print(f"  Size: {os.path.getsize(p)} bytes")
        print(f"  Modified: {dt}")
    else:
        print(f"File {p} does not exist!")
