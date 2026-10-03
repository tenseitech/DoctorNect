import os
import glob
import re

def main():
    lib_dir = os.path.join('c:\\doctor\\doctor', 'lib')
    dart_files = glob.glob(f'{lib_dir}\\**\\*.dart', recursive=True)
    
    file_names = {os.path.basename(f): f for f in dart_files}
    
    # Read all dart files
    all_content = ""
    for f in dart_files:
        try:
            with open(f, 'r', encoding='utf-8') as file:
                all_content += file.read() + "\n"
        except Exception:
            pass
            
    unused_files = []
    for f_path in dart_files:
        f_name = os.path.basename(f_path)
        # Check if imported
        if f_name == 'main.dart':
            continue
        # check if f_name is present in all_content at least twice (once where it's defined/exported, once where imported)
        # actually, just check if the string f_name is in the content of OTHER files
        
        # better approach: check if f_name is in any other file's content
        used = False
        for other_f in dart_files:
            if other_f == f_path:
                continue
            try:
                with open(other_f, 'r', encoding='utf-8') as ofile:
                    if f_name in ofile.read():
                        used = True
                        break
            except Exception:
                pass
        
        if not used:
            unused_files.append(f_path)
            
    with open('unused_dart_files.txt', 'w', encoding='utf-8') as f:
        for uf in unused_files:
            f.write(uf + "\n")
            
if __name__ == "__main__":
    main()
