import os
path = r"C:\sistema\backend\routers"
if os.path.exists(path):
    for f in os.listdir(path):
        print(f)
else:
    print("Does not exist")
