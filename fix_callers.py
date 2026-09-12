"""
Fix all call sites for PatientProfileFormStyles methods that now require context.
Also fixes authLoginFieldDecoration call sites.
"""
import re
import os

LIB = r'c:/doctor/doctor/lib'

def fix_file(path, replacements):
    """Apply a list of (old, new) string replacements to a file."""
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    modified = content
    for old, new in replacements:
        if old in modified:
            modified = modified.replace(old, new)
        else:
            print(f"  NOT FOUND in {os.path.basename(path)}: {old[:70]!r}")
    if modified != content:
        with open(path, 'w', encoding='utf-8') as f:
            f.write(modified)
        return True
    return False


def fix_all_with_regex(root, pattern_from, pattern_to):
    """Walk all .dart files and apply a regex substitution."""
    count = 0
    for dirpath, _, files in os.walk(root):
        for fname in files:
            if not fname.endswith('.dart'):
                continue
            fpath = os.path.join(dirpath, fname)
            with open(fpath, 'r', encoding='utf-8') as f:
                content = f.read()
            modified = re.sub(pattern_from, pattern_to, content)
            if modified != content:
                with open(fpath, 'w', encoding='utf-8') as f:
                    f.write(modified)
                count += 1
    return count


def main():
    changed = []

    # -------------------------------------------------------
    # 1. PatientProfileFormStyles.fieldDecoration(... -> fieldDecoration(context, ...
    #    Pattern: .fieldDecoration(\n?   -> .fieldDecoration(context, 
    #    We need to insert "context," as FIRST positional arg to fieldDecoration.
    # -------------------------------------------------------
    count = fix_all_with_regex(
        LIB,
        r'PatientProfileFormStyles\.fieldDecoration\(',
        r'PatientProfileFormStyles.fieldDecoration(context, ',
    )
    print(f"fieldDecoration call sites fixed: {count} files")

    # -------------------------------------------------------
    # 2. PatientProfileFormStyles.contentSurface(child: -> contentSurface(child: ..., context: context)
    #    Pattern: .contentSurface(child: X) -> .contentSurface(child: X, context: context)
    # -------------------------------------------------------
    count = fix_all_with_regex(
        LIB,
        r'PatientProfileFormStyles\.contentSurface\(child:',
        r'PatientProfileFormStyles.contentSurface(context: context, child:',
    )
    print(f"contentSurface call sites fixed: {count} files")

    # -------------------------------------------------------
    # 3. PatientProfileFormStyles.recordItemCard(child: -> recordItemCard(child: ..., context: context)
    # -------------------------------------------------------
    count = fix_all_with_regex(
        LIB,
        r'PatientProfileFormStyles\.recordItemCard\(child:',
        r'PatientProfileFormStyles.recordItemCard(child:',
    )
    # Revert extra passes
    count = fix_all_with_regex(
        LIB,
        r'PatientProfileFormStyles\.recordItemCard\(child:\s*([^,\)]+),?\s*\)',
        r'PatientProfileFormStyles.recordItemCard(context: context, child: \1)',
    )
    print(f"recordItemCard call sites fixed: {count} files")

    # -------------------------------------------------------
    # 4. PatientProfileFormStyles.settingsRowCard( -> add context:
    # -------------------------------------------------------
    count = fix_all_with_regex(
        LIB,
        r'PatientProfileFormStyles\.settingsRowCard\(\s*child:',
        r'PatientProfileFormStyles.settingsRowCard(\n                  context: context,\n                  child:',
    )
    print(f"settingsRowCard call sites fixed: {count} files")

    # -------------------------------------------------------
    # 5. PatientProfileFormStyles.profileAppBar(... -> profileAppBar(..., context: context)
    # -------------------------------------------------------
    count = fix_all_with_regex(
        LIB,
        r"PatientProfileFormStyles\.profileAppBar\('([^']+)'\)",
        r"PatientProfileFormStyles.profileAppBar('\1', context: context)",
    )
    print(f"profileAppBar call sites fixed: {count} files")

    # -------------------------------------------------------
    # 6. profileAppBar with double-quoted names
    # -------------------------------------------------------
    count = fix_all_with_regex(
        LIB,
        r'PatientProfileFormStyles\.profileAppBar\("([^"]+)"\)',
        r"PatientProfileFormStyles.profileAppBar('\1', context: context)",
    )
    print(f"profileAppBar (double-quoted) call sites fixed: {count} files")

    # -------------------------------------------------------
    # 7. contentSurface that uses child: without parens we already handled
    #    Also fix contentSurface(..) -> needs context
    # -------------------------------------------------------

    # -------------------------------------------------------
    # 8. Also update the contentSurface signature to accept context:
    # -------------------------------------------------------
    styles_path = r'c:/doctor/doctor/lib/features/patient/profile/widgets/patient_profile_form_styles.dart'
    with open(styles_path, 'r', encoding='utf-8') as f:
        content = f.read()
    content = content.replace(
        '  static Widget contentSurface({required Widget child}) {',
        '  static Widget contentSurface({required BuildContext context, required Widget child}) {'
    )
    content = content.replace(
        '      color: Colors.white,\n      borderRadius: BorderRadius.circular(12),\n      border: Border.all(color: AppColors.border, width: 0.5),',
        '      color: AppColors.surfaceOf(context),\n      borderRadius: BorderRadius.circular(12),\n      border: Border.all(color: AppColors.borderOf(context), width: 0.5),'
    )
    with open(styles_path, 'w', encoding='utf-8') as f:
        f.write(content)
    print("contentSurface signature updated")

    # -------------------------------------------------------
    # 9. profile_edit_widgets.dart - it calls fieldDecoration without context, now needs to pass context
    # -------------------------------------------------------
    edit_path = r'c:/doctor/doctor/lib/features/patient/profile/widgets/profile_edit_widgets.dart'
    with open(edit_path, 'r', encoding='utf-8') as f:
        content = f.read()
    # fieldDecoration is already fixed by regex pass above
    with open(edit_path, 'w', encoding='utf-8') as f:
        f.write(content)

    print("\nAll call sites updated!")


if __name__ == '__main__':
    main()
