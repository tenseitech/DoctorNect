"""
Migrate ScaffoldMessenger.of(context).showSnackBar to AppToast across the codebase.
"""
import re, os

LIB = r'c:/doctor/doctor/lib'

def read(p):
    with open(p, 'r', encoding='utf-8') as f: return f.read()
def write(p, c):
    with open(p, 'w', encoding='utf-8') as f: f.write(c)

def main():
    count = 0
    modified_files = 0

    for dirpath, _, files in os.walk(LIB):
        for fname in files:
            if not fname.endswith('.dart'): continue
            if fname == 'app_toast.dart': continue
            fpath = os.path.join(dirpath, fname)
            c = read(fpath)
            if 'showSnackBar' not in c: continue

            original = c
            
            # Simple pattern: ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg)))
            # or const SnackBar(...)
            # Let's replace simple single-line SnackBar calls with AppToast.show(ctx, msg)
            
            # 1. Simple const SnackBar(content: Text('text'))
            c = re.sub(
                r'ScaffoldMessenger\.of\((\w+)\)\.showSnackBar\(\s*const\s+SnackBar\(\s*content:\s*Text\(([^)]+)\),?\s*\),?\s*\);',
                r'AppToast.info(\1, \2);',
                c
            )

            # 2. Simple SnackBar(content: Text('text'))
            c = re.sub(
                r'ScaffoldMessenger\.of\((\w+)\)\.showSnackBar\(\s*SnackBar\(\s*content:\s*Text\(([^)]+)\),?\s*\),?\s*\);',
                r'AppToast.info(\1, \2);',
                c
            )

            if c != original:
                # Add import if missing
                if "import '../../core/notifications/app_toast.dart';" not in c and "import '../../../core/notifications/app_toast.dart';" not in c:
                    # Calculate relative import
                    rel_dir = os.path.relpath(r'c:/doctor/doctor/lib/core/notifications', dirpath).replace('\\', '/')
                    import_line = f"import '{rel_dir}/app_toast.dart';\n"
                    c = import_line + c

                write(fpath, c)
                modified_files += 1
                print(f"Updated: {fname}")

    print(f"\nTotal files updated: {modified_files}")

if __name__ == '__main__':
    main()
