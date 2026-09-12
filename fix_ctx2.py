"""
Fix remaining context-injection errors from analyze run task-700.
Approach:
1. Fix `dobPickerRow` in patient_profile_form_styles.dart to accept context
2. Fix `contactDecoration` in profile_edit_widgets.dart to accept context
3. Fix `location_dropdown_fields.dart` - _decoration is a method on StatelessWidget, so it has `context`
4. Fix `profileCard` call in patient_profile_form_styles.dart line 162
5. Fix all `contentSurface(child:` calls that are missing `context:`
6. Fix all appointment_detail_screen, booking_flow_screen calls that are missing context:
"""
import re, os

LIB = r'c:/doctor/doctor/lib'


def read(path):
    with open(path, 'r', encoding='utf-8') as f:
        return f.read()


def write(path, content):
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)


def sub(content, old, new, path=''):
    if old in content:
        return content.replace(old, new)
    print(f"  NOT FOUND in {os.path.basename(path)}: {old[:70]!r}")
    return content


# -------------------------------------------------------
# 1. patient_profile_form_styles.dart
#    - dobPickerRow needs context param
#    - profileCard needs to forward context
# -------------------------------------------------------
styles_path = os.path.join(LIB, 'features/patient/profile/widgets/patient_profile_form_styles.dart')
c = read(styles_path)

# dobPickerRow - add context param
c = sub(c, '''  static Widget dobPickerRow({
    required String label,
    required String valueText,
    required VoidCallback onTap,
    bool isRequired = false,
  }) {''',
'''  static Widget dobPickerRow({
    required BuildContext context,
    required String label,
    required String valueText,
    required VoidCallback onTap,
    bool isRequired = false,
  }) {''', styles_path)

# profileCard - forward context
c = sub(c,
    '  static Widget profileCard({required Widget child}) {\n    return contentSurface(child: child);\n  }',
    '  static Widget profileCard({required Widget child, required BuildContext context}) {\n    return contentSurface(context: context, child: child);\n  }',
    styles_path)

write(styles_path, c)
print("Fixed: patient_profile_form_styles.dart")


# -------------------------------------------------------
# 2. profile_edit_widgets.dart - contactDecoration needs context param
# -------------------------------------------------------
edit_path = os.path.join(LIB, 'features/patient/profile/widgets/profile_edit_widgets.dart')
c = read(edit_path)

c = sub(c, '''  static InputDecoration contactDecoration({
    required String labelText,
    required bool editing,
    Widget? suffixIcon,
    String? counterText,
  }) {
    return PatientProfileFormStyles.fieldDecoration(context, ''',
'''  static InputDecoration contactDecoration({
    required BuildContext context,
    required String labelText,
    required bool editing,
    Widget? suffixIcon,
    String? counterText,
  }) {
    return PatientProfileFormStyles.fieldDecoration(context, ''', edit_path)

write(edit_path, c)
print("Fixed: profile_edit_widgets.dart")


# -------------------------------------------------------
# 3. location_dropdown_fields.dart - `_decoration` is a method of StatelessWidget
#    but it doesn't have context passed. StatelessWidget does have context in build.
#    Fix: pass context to _decoration or use `context` already available via build method.
#    The widget is a StatelessWidget, so _decoration doesn't have context.
#    Easiest fix: revert fillColor to use Theme.of(context) directly, 
#    or change _decoration to accept BuildContext context.
# -------------------------------------------------------
loc_path = os.path.join(LIB, 'widgets/location_dropdown_fields.dart')
c = read(loc_path)

# _decoration is called inside build(), let's fix _decoration to accept context
c = sub(c,
    '  InputDecoration _decoration(String label,\n      {String? hint, bool isRequired = false}) {',
    '  InputDecoration _decoration(BuildContext context, String label,\n      {String? hint, bool isRequired = false}) {',
    loc_path)

# Fix border references to use context
c = sub(c,
    '          borderSide: BorderSide(color: AppColors.border),\n        ),\n        enabledBorder: OutlineInputBorder(\n          borderRadius: BorderRadius.circular(AppConstants.inputRadius),\n          borderSide: BorderSide(color: AppColors.border),',
    '          borderSide: BorderSide(color: AppColors.borderOf(context)),\n        ),\n        enabledBorder: OutlineInputBorder(\n          borderRadius: BorderRadius.circular(AppConstants.inputRadius),\n          borderSide: BorderSide(color: AppColors.borderOf(context)),',
    loc_path)

# Now fix all call sites of _decoration inside this file
c = re.sub(r'_decoration\(([^,)]+),', r'_decoration(context, \1,', c)
c = re.sub(r'_decoration\(context, context, ', '_decoration(context, ', c)  # avoid double context

write(loc_path, c)
print("Fixed: location_dropdown_fields.dart")


# -------------------------------------------------------
# 4. Fix appointment_detail_screen - contentSurface missing context:
# -------------------------------------------------------
appt_path = os.path.join(LIB, 'features/patient/appointments/appointment_detail_screen.dart')
c = read(appt_path)
c = re.sub(
    r'PatientProfileFormStyles\.contentSurface\(\s*child:',
    'PatientProfileFormStyles.contentSurface(context: context, child:',
    c
)
write(appt_path, c)
print("Fixed: appointment_detail_screen.dart")


# -------------------------------------------------------
# 5. Fix booking_flow_screen - contentSurface missing context:
# -------------------------------------------------------
booking_path = os.path.join(LIB, 'features/patient/booking/booking_flow_screen.dart')
c = read(booking_path)
c = re.sub(
    r'PatientProfileFormStyles\.contentSurface\(\s*child:',
    'PatientProfileFormStyles.contentSurface(context: context, child:',
    c
)
write(booking_path, c)
print("Fixed: booking_flow_screen.dart")


# -------------------------------------------------------
# 6. Fix remaining contentSurface callers across all files
# -------------------------------------------------------
count = 0
for dirpath, _, files in os.walk(LIB):
    for fname in files:
        if not fname.endswith('.dart'):
            continue
        fpath = os.path.join(dirpath, fname)
        c = read(fpath)
        modified = re.sub(
            r'PatientProfileFormStyles\.contentSurface\(\s*child:',
            'PatientProfileFormStyles.contentSurface(context: context, child:',
            c
        )
        if modified != c:
            write(fpath, modified)
            count += 1
if count:
    print(f"Fixed contentSurface in {count} additional files")


# -------------------------------------------------------
# 7. Fix edit_profile_screen.dart - contactDecoration now requires context
# -------------------------------------------------------
edit_profile_path = os.path.join(LIB, 'features/patient/profile/edit_profile_screen.dart')
c = read(edit_profile_path)
c = re.sub(
    r'ProfileEditWidgets\.contactDecoration\(',
    'ProfileEditWidgets.contactDecoration(\n                            context: context,',
    c
)
write(edit_profile_path, c)
print("Fixed: edit_profile_screen.dart")


# -------------------------------------------------------
# 8. Fix dobPickerRow call sites to add context
# -------------------------------------------------------
count = 0
for dirpath, _, files in os.walk(LIB):
    for fname in files:
        if not fname.endswith('.dart'):
            continue
        fpath = os.path.join(dirpath, fname)
        c = read(fpath)
        modified = re.sub(
            r'PatientProfileFormStyles\.dobPickerRow\(',
            'PatientProfileFormStyles.dobPickerRow(\n          context: context,',
            c
        )
        if modified != c:
            write(fpath, modified)
            count += 1
            print(f"  Fixed dobPickerRow in: {fname}")
print(f"dobPickerRow fixed in {count} files")


# -------------------------------------------------------
# 9. Fix profileCard call sites
# -------------------------------------------------------
count = 0
for dirpath, _, files in os.walk(LIB):
    for fname in files:
        if not fname.endswith('.dart'):
            continue
        fpath = os.path.join(dirpath, fname)
        c = read(fpath)
        modified = re.sub(
            r'PatientProfileFormStyles\.profileCard\(\s*child:',
            'PatientProfileFormStyles.profileCard(context: context, child:',
            c
        )
        if modified != c:
            write(fpath, modified)
            count += 1
            print(f"  Fixed profileCard in: {fname}")
print(f"profileCard fixed in {count} files")

print("\nAll done!")
