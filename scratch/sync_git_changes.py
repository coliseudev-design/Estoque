import os
import subprocess
import shutil

src_root = r"c:\Users\rober\.gemini\antigravity\scratch\Coliseu_Sales"
dest_root = r"C:\Users\rober\OneDrive\Documentos\GitHub\ColiseuSales"

def get_modified_files():
    result = subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True, cwd=src_root)
    lines = result.stdout.strip().split("\n")
    files = []
    for line in lines:
        if not line:
            continue
        # Split by maxsplit=1 to separate status code from file path
        parts = line.split(maxsplit=1)
        if len(parts) < 2:
            continue
        filepath = parts[1].strip().strip('"')
        if filepath.startswith("scratch/") or filepath.startswith(".system_generated/"):
            continue
        files.append(filepath)
    return files

files = get_modified_files()
print(f"Found {len(files)} files to sync:")

for rel_path in files:
    src_file = os.path.join(src_root, rel_path)
    dest_file = os.path.join(dest_root, rel_path)
    
    if os.path.exists(src_file):
        dest_dir = os.path.dirname(dest_file)
        if not os.path.exists(dest_dir):
            os.makedirs(dest_dir)
            print(f"Created folder: {dest_dir}")
        shutil.copy2(src_file, dest_file)
        print(f"Synced: {rel_path}")
    else:
        print(f"Warning: file {src_file} does not exist locally.")

print("Sync completed!")
