import os

def find_file(filename, search_path):
    for root, dirs, files in os.walk(search_path):
        if filename in files:
            print(os.path.join(root, filename))

print("Searching C:\\Users...")
find_file("coliseu_sales.db", "C:\\Users")
print("Search complete.")
