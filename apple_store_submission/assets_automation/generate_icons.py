#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import json
import shutil
import subprocess

# Lista de ícones conforme especificado no Contents.json da Apple
ICON_CONFIGS = [
    {"size": "20x20", "idiom": "iphone", "filename": "Icon-App-20x20@2x.png", "scale": "2x", "pixels": 40},
    {"size": "20x20", "idiom": "iphone", "filename": "Icon-App-20x20@3x.png", "scale": "3x", "pixels": 60},
    {"size": "29x29", "idiom": "iphone", "filename": "Icon-App-29x29@1x.png", "scale": "1x", "pixels": 29},
    {"size": "29x29", "idiom": "iphone", "filename": "Icon-App-29x29@2x.png", "scale": "2x", "pixels": 58},
    {"size": "29x29", "idiom": "iphone", "filename": "Icon-App-29x29@3x.png", "scale": "3x", "pixels": 87},
    {"size": "40x40", "idiom": "iphone", "filename": "Icon-App-40x40@2x.png", "scale": "2x", "pixels": 80},
    {"size": "40x40", "idiom": "iphone", "filename": "Icon-App-40x40@3x.png", "scale": "3x", "pixels": 120},
    {"size": "57x57", "idiom": "iphone", "filename": "Icon-App-57x57@1x.png", "scale": "1x", "pixels": 57},
    {"size": "57x57", "idiom": "iphone", "filename": "Icon-App-57x57@2x.png", "scale": "2x", "pixels": 114},
    {"size": "60x60", "idiom": "iphone", "filename": "Icon-App-60x60@2x.png", "scale": "2x", "pixels": 120},
    {"size": "60x60", "idiom": "iphone", "filename": "Icon-App-60x60@3x.png", "scale": "3x", "pixels": 180},
    {"size": "20x20", "idiom": "ipad", "filename": "Icon-App-20x20@1x.png", "scale": "1x", "pixels": 20},
    {"size": "20x20", "idiom": "ipad", "filename": "Icon-App-20x20@2x.png", "scale": "2x", "pixels": 40},
    {"size": "29x29", "idiom": "ipad", "filename": "Icon-App-29x29@1x.png", "scale": "1x", "pixels": 29},
    {"size": "29x29", "idiom": "ipad", "filename": "Icon-App-29x29@2x.png", "scale": "2x", "pixels": 58},
    {"size": "40x40", "idiom": "ipad", "filename": "Icon-App-40x40@1x.png", "scale": "1x", "pixels": 40},
    {"size": "40x40", "idiom": "ipad", "filename": "Icon-App-40x40@2x.png", "scale": "2x", "pixels": 80},
    {"size": "50x50", "idiom": "ipad", "filename": "Icon-App-50x50@1x.png", "scale": "1x", "pixels": 50},
    {"size": "50x50", "idiom": "ipad", "filename": "Icon-App-50x50@2x.png", "scale": "2x", "pixels": 100},
    {"size": "72x72", "idiom": "ipad", "filename": "Icon-App-72x72@1x.png", "scale": "1x", "pixels": 72},
    {"size": "72x72", "idiom": "ipad", "filename": "Icon-App-72x72@2x.png", "scale": "2x", "pixels": 144},
    {"size": "76x76", "idiom": "ipad", "filename": "Icon-App-76x76@1x.png", "scale": "1x", "pixels": 76},
    {"size": "76x76", "idiom": "ipad", "filename": "Icon-App-76x76@2x.png", "scale": "2x", "pixels": 152},
    {"size": "83.5x83.5", "idiom": "ipad", "filename": "Icon-App-83.5x83.5@2x.png", "scale": "2x", "pixels": 167},
    {"size": "1024x1024", "idiom": "ios-marketing", "filename": "Icon-App-1024x1024@1x.png", "scale": "1x", "pixels": 1024}
]

def resize_pillow(src_path, dest_path, pixels):
    try:
        from PIL import Image
        with Image.open(src_path) as img:
            if hasattr(Image, "Resampling"):
                resized_img = img.resize((pixels, pixels), Image.Resampling.LANCZOS)
            else:
                resized_img = img.resize((pixels, pixels), Image.ANTIALIAS)
            resized_img.save(dest_path)
            return True
    except Exception as e:
        print(f"Erro ao redimensionar com Pillow para {pixels}x{pixels}: {e}")
        return False

def resize_sips(src_path, dest_path, pixels):
    try:
        shutil.copyfile(src_path, dest_path)
        cmd = ["sips", "-z", str(pixels), str(pixels), dest_path]
        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return result.returncode == 0
    except Exception as e:
        print(f"Erro ao redimensionar com sips para {pixels}x{pixels}: {e}")
        return False

def check_pillow():
    try:
        from PIL import Image
        return True
    except ImportError:
        return False

def has_sips():
    return shutil.which("sips") is not None

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    src_image = os.path.join(script_dir, "icon.png")
    
    if not os.path.exists(src_image):
        print(f"[-] Arquivo de origem não encontrado em: {src_image}")
        print("[!] Por favor, adicione uma imagem base 'icon.png' (1024x1024 px) nesta mesma pasta.")
        print("[!] Caminho esperado: apple_store_submission/assets_automation/icon.png")
        sys.exit(1)
        
    print(f"[+] Imagem base encontrada: {src_image}")
    
    output_dir = os.path.join(script_dir, "AppIcon.appiconset")
    os.makedirs(output_dir, exist_ok=True)
    print(f"[+] Pasta de destino local criada: {output_dir}")
    
    use_pillow = check_pillow()
    use_sips = has_sips()
    
    if use_pillow:
        print("[*] Utilizando a biblioteca Pillow (Python) para redimensionamento.")
        resize_fn = resize_pillow
    elif use_sips:
        print("[*] Pillow não instalada. Utilizando o utilitário nativo macOS 'sips'.")
        resize_fn = resize_sips
    else:
        print("[-] Erro: Nenhuma ferramenta de redimensionamento de imagem disponível.")
        print("    Instale a biblioteca Pillow com: pip install Pillow")
        print("    Ou execute em um macOS (onde o comando 'sips' está disponível por padrão).")
        sys.exit(1)
        
    unique_files = {}
    for cfg in ICON_CONFIGS:
        unique_files[cfg["filename"]] = cfg["pixels"]
        
    print(f"[*] Gerando {len(unique_files)} resoluções de ícones...")
    
    success_count = 0
    for filename, pixels in unique_files.items():
        dest_path = os.path.join(output_dir, filename)
        if resize_fn(src_image, dest_path, pixels):
            print(f"  [✓] Gerado: {filename} ({pixels}x{pixels} px)")
            success_count += 1
        else:
            print(f"  [✗] Falha ao gerar: {filename} ({pixels}x{pixels} px)")
            
    if success_count < len(unique_files):
        print("[-] Algumas imagens falharam ao ser geradas. Verifique os erros acima.")
        sys.exit(1)
        
    contents_json_path = os.path.join(output_dir, "Contents.json")
    contents_data = {
        "images": [
            {
                "size": cfg["size"],
                "idiom": cfg["idiom"],
                "filename": cfg["filename"],
                "scale": cfg["scale"]
            } for cfg in ICON_CONFIGS
        ],
        "info": {
            "version": 1,
            "author": "xcode"
        }
    }
    
    try:
        with open(contents_json_path, "w", encoding="utf-8") as f:
            json.dump(contents_data, f, indent=4)
        print(f"[✓] Contents.json criado em: {contents_json_path}")
    except Exception as e:
        print(f"[-] Erro ao salvar Contents.json: {e}")
        sys.exit(1)
        
    print("\n[✓] Todos os ícones foram gerados com sucesso na pasta local!")
    
    project_ios_icon_dir = os.path.join(script_dir, "..", "..", "mobile", "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    project_ios_icon_dir = os.path.abspath(project_ios_icon_dir)
    
    if os.path.exists(project_ios_icon_dir):
        print(f"\n[*] Detectada pasta do projeto Flutter no caminho: {project_ios_icon_dir}")
        
        auto_copy = False
        if len(sys.argv) > 1 and sys.argv[1] in ["-y", "--yes", "--copy"]:
            auto_copy = True
        elif not sys.stdin.isatty():
            auto_copy = False
        else:
            try:
                response = input("Deseja copiar automaticamente os novos ícones para substituir os ícones do aplicativo? (S/N): ").strip().upper()
                auto_copy = response in ['S', 'SIM', 'Y', 'YES']
            except (KeyboardInterrupt, EOFError):
                auto_copy = False
                
        if auto_copy:
            try:
                if os.path.exists(project_ios_icon_dir):
                    shutil.rmtree(project_ios_icon_dir)
                shutil.copytree(output_dir, project_ios_icon_dir)
                print("[✓] Ícones atualizados com sucesso no projeto iOS!")
            except Exception as e:
                print(f"[-] Erro ao copiar ícones para o projeto: {e}")
        else:
            print("[*] Cópia automática ignorada. Você pode copiar a pasta 'AppIcon.appiconset' gerada para o seu Assets.xcassets no Xcode.")
    else:
        print(f"\n[!] Pasta do projeto iOS não encontrada no caminho relativo esperado: {project_ios_icon_dir}")
        print("    Você pode copiar a pasta 'AppIcon.appiconset' gerada para o seu Assets.xcassets no Xcode.")

if __name__ == "__main__":
    main()
