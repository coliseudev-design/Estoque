import os
import shutil

src_root = r"c:\Users\rober\.gemini\antigravity\scratch\Coliseu_Sales"
dest_root = r"C:\Users\rober\OneDrive\Documentos\GitHub\ColiseuSales"

files_to_copy = [
    r"middleware\src\routes\admin\adminOrders.js",
    r"worker.tests\FirebirdOptionsTests.cs",
    r"worker\Jobs\SyncSalesRankingsJob.cs",
    r"worker\ColiseuSales.Worker.csproj",
    r"ColiseuSales.Configurator\ColiseuSales.Configurator.csproj",
    r"ColiseuSales.Configurator.exe"
]

for relative_path in files_to_copy:
    src_file = os.path.join(src_root, relative_path)
    dest_file = os.path.join(dest_root, relative_path)
    
    # Create parent directories in destination if they don't exist
    dest_dir = os.path.dirname(dest_file)
    if not os.path.exists(dest_dir):
        os.makedirs(dest_dir)
        print(f"Created directory: {dest_dir}")
        
    shutil.copy2(src_file, dest_file)
    print(f"Copied {src_file} -> {dest_file}")
