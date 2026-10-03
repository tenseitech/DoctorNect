"""
Fix remaining compile errors from analyze task-725.
"""
import re, os

LIB = r'c:/doctor/doctor/lib'

def read(p):
    with open(p, 'r', encoding='utf-8') as f: return f.read()
def write(p, c):
    with open(p, 'w', encoding='utf-8') as f: f.write(c)
def sub(c, old, new, p=''):
    if old in c: return c.replace(old, new)
    print(f"  NOT FOUND [{os.path.basename(p)}]: {old[:70]!r}")
    return c

# -------------------------------------------------------
# 1. location_dropdown_fields.dart
#    - Remove duplicate 'context' in _decoration signature
#    - Fix call sites (they now pass context as first arg correctly)
# -------------------------------------------------------
p = os.path.join(LIB, 'widgets/location_dropdown_fields.dart')
c = read(p)
# Fix the duplicate 'context, BuildContext context' in signature
c = sub(c,
    '  InputDecoration _decoration(context, BuildContext context, String label,',
    '  InputDecoration _decoration(BuildContext context, String label,',
    p)
write(p, c)
print("Fixed: location_dropdown_fields.dart")

# -------------------------------------------------------
# 2. patient_filters_bar.dart
#    - _searchField() and _sortRow() are called with context in parent but
#      don't have access themselves — they're private methods on a StatelessWidget.
#      Need to pass context to them.
# -------------------------------------------------------
p = os.path.join(LIB, 'features/doctor/patients/widgets/patient_filters_bar.dart')
c = read(p)

# Fix _searchField to accept context
c = sub(c,
    '  Widget _searchField() {\n    return TextField(',
    '  Widget _searchField(BuildContext context) {\n    return TextField(',
    p)
c = sub(c,
    '  Widget _filterChips() {',
    '  Widget _filterChips(BuildContext context) {',
    p)
c = sub(c,
    '  Widget _sortRow({bool compact = false}) {',
    '  Widget _sortRow(BuildContext context, {bool compact = false}) {',
    p)

# Fix call sites inside _buildCompactFilters
c = sub(c,
    '        _searchField(),\n        const SizedBox(height: 10),\n        _filterChips(),\n        const SizedBox(height: 8),\n        _sortRow(),',
    '        _searchField(context),\n        const SizedBox(height: 10),\n        _filterChips(context),\n        const SizedBox(height: 8),\n        _sortRow(context),',
    p)
# Fix call sites inside _buildWideFilters
c = sub(c,
    'Expanded(flex: 3, child: _searchField()),',
    'Expanded(flex: 3, child: _searchField(context)),',
    p)
c = sub(c,
    'Expanded(flex: 2, child: _sortRow(compact: true)),',
    'Expanded(flex: 2, child: _sortRow(context, compact: true)),',
    p)
c = sub(c,
    '        _filterChips(),',
    '        _filterChips(context),',
    p)
write(p, c)
print("Fixed: patient_filters_bar.dart")


# -------------------------------------------------------
# 3. auth_login_page_shell.dart line 23 - authLoginInputDecoration
#    calls authLoginFieldDecoration without context
# -------------------------------------------------------
p = os.path.join(LIB, 'features/auth/widgets/auth_login_page_shell.dart')
c = read(p)

# authLoginInputDecoration is a free function - needs context param
c = sub(c,
    'InputDecoration authLoginInputDecoration({\n  required Color accentColor,',
    'InputDecoration authLoginInputDecoration({\n  required BuildContext context,\n  required Color accentColor,',
    p)
c = sub(c,
    '    authLoginFieldDecoration(\n      accentColor: accentColor,',
    '    authLoginFieldDecoration(\n      context: context,\n      accentColor: accentColor,',
    p)
write(p, c)
print("Fixed: auth_login_page_shell.dart signature")

# Now fix all callers of authLoginInputDecoration across the codebase
count = 0
for dirpath, _, files in os.walk(LIB):
    for fname in files:
        if not fname.endswith('.dart'): continue
        fpath = os.path.join(dirpath, fname)
        c = read(fpath)
        modified = re.sub(
            r'authLoginInputDecoration\(',
            'authLoginInputDecoration(\n      context: context,',
            c
        )
        # Avoid double-adding context
        modified = re.sub(
            r'authLoginInputDecoration\(\s*\n\s*context: context,\s*\n\s*context: context,',
            'authLoginInputDecoration(\n      context: context,',
            modified
        )
        if modified != c:
            write(fpath, modified)
            count += 1
            print(f"  Fixed authLoginInputDecoration in: {fname}")
print(f"authLoginInputDecoration callers fixed: {count} files")


# -------------------------------------------------------
# 4. auth_login_password_field.dart - authLoginFieldDecoration call missing context
# -------------------------------------------------------
p = os.path.join(LIB, 'features/auth/widgets/auth_login_password_field.dart')
c = read(p)
c = sub(c,
    '          decoration: authLoginFieldDecoration(\n            accentColor: widget.accentColor,',
    '          decoration: authLoginFieldDecoration(\n            context: context,\n            accentColor: widget.accentColor,',
    p)
write(p, c)
print("Fixed: auth_login_password_field.dart")


# -------------------------------------------------------
# 5. ambulance_login_screen.dart - authLoginFieldDecoration missing context
# -------------------------------------------------------
p = os.path.join(LIB, 'features/ambulance/ambulance_login_screen.dart')
if os.path.exists(p):
    c = read(p)
    # Fix any authLoginFieldDecoration calls that are missing context
    modified = re.sub(
        r'authLoginFieldDecoration\(\s*\n?\s*accentColor:',
        'authLoginFieldDecoration(\n            context: context,\n            accentColor:',
        c
    )
    modified = re.sub(
        r'authLoginInputDecoration\(\s*\n?\s*accentColor:',
        'authLoginInputDecoration(\n            context: context,\n            accentColor:',
        modified
    )
    if modified != c:
        write(p, modified)
        print("Fixed: ambulance_login_screen.dart")
    else:
        print("  No changes needed in ambulance_login_screen.dart")


# -------------------------------------------------------
# 6. Fix any remaining authLoginFieldDecoration calls missing context (global scan)
# -------------------------------------------------------
count = 0
for dirpath, _, files in os.walk(LIB):
    for fname in files:
        if not fname.endswith('.dart'): continue
        fpath = os.path.join(dirpath, fname)
        c = read(fpath)
        # Find authLoginFieldDecoration( NOT followed by context: within 3 lines
        # Simple approach: replace patterns without context
        modified = re.sub(
            r'authLoginFieldDecoration\(\s*\n?\s*(?!context:)accentColor:',
            'authLoginFieldDecoration(\n            context: context,\n            accentColor:',
            c
        )
        if modified != c:
            write(fpath, modified)
            count += 1
            print(f"  Fixed authLoginFieldDecoration in: {fname}")
print(f"authLoginFieldDecoration additional callers: {count}")

print("\nAll done!")
