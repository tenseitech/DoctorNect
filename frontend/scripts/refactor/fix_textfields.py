import re
import os

# ============================================================
# This script fixes TextField/TextFormField dark-mode contrast:
# 1. In InputDecoration helpers (static functions): converts 
#    hardcoded fillColor to a sentinel so we can pass context.
# 2. In files with hardcoded fillColor -> AppColors.surfaceOf(context)
# 3. In files with hardcoded fillColor -> AppColors.cardBgOf(context)
# 4. Fixes static hintStyle colors in InputDecoration 
# ============================================================

REPLACEMENTS = [
    # ----- auth_login_form_field.dart -----
    # fillColor is inside a free function, needs context param
    (
        r'c:/doctor/doctor/lib/features/auth/widgets/auth_login_form_field.dart',
        [
            # Add context param to authLoginFieldDecoration
            ('InputDecoration authLoginFieldDecoration({\n  required Color accentColor,',
             'InputDecoration authLoginFieldDecoration({\n  required BuildContext context,\n  required Color accentColor,'),
            # Fix fillColor
            ('fillColor: readOnly ? AppColors.cardBackground : const Color(0xFFF8FAFC),',
             'fillColor: readOnly ? AppColors.cardBgOf(context) : AppColors.surfaceOf(context),'),
            # Fix hardcoded border/hint colors that need context
            ('color: AppColors.textSecondary.withValues(alpha: 0.7),',
             'color: AppColors.textSecondaryOf(context).withValues(alpha: 0.7),'),
            ('border: border(AppColors.border),',
             'border: border(AppColors.borderOf(context)),'),
            ('enabledBorder: border(const Color(0xFFE2E8F0)),',
             'enabledBorder: border(AppColors.borderOf(context)),'),
            ('disabledBorder: border(AppColors.border),',
             'disabledBorder: border(AppColors.borderOf(context)),'),
            # The call site in AuthLoginFormField.build
            ('decoration: authLoginFieldDecoration(\n            accentColor: accentColor,',
             'decoration: authLoginFieldDecoration(\n            context: context,\n            accentColor: accentColor,'),
        ],
    ),

    # ----- otp_input.dart -----
    (
        r'c:/doctor/doctor/lib/widgets/otp_input.dart',
        [
            ('fillColor: const Color(0xFFF8FAFC),',
             'fillColor: AppColors.cardBgOf(context),'),
        ],
    ),

    # ----- patient_profile_form_styles.dart -----
    # This is a static class; fieldDecoration doesn't take context.
    # We need to add context to fieldDecoration, contentSurface etc.
    # Easiest: switch fillColor to use a theme-aware approach.
    # Because it's a static class, easiest fix: switch to ThemeData lookup inside Widget where used,
    # OR change fillColor to null and rely on the theme's inputDecorationTheme.
    # Best approach: change `fieldDecoration` to accept context.
    (
        r'c:/doctor/doctor/lib/features/patient/profile/widgets/patient_profile_form_styles.dart',
        [
            # fieldDecoration - add context param
            ('  static InputDecoration fieldDecoration({\n    required String labelText,',
             '  static InputDecoration fieldDecoration(BuildContext context, {\n    required String labelText,'),
            # fillColor
            ('    fillColor: Colors.white,',
             '    fillColor: AppColors.surfaceOf(context),'),
            # enabledBorder border color  
            ('          borderSide: BorderSide(color: AppColors.border),',
             '          borderSide: BorderSide(color: AppColors.borderOf(context)),'),
            # contentSurface - needs context
            ('  static Widget contentSurface({required Widget child}) {\n    return Container(\n      decoration: BoxDecoration(\n        color: Colors.white,',
             '  static Widget contentSurface({required Widget child, required BuildContext context}) {\n    return Container(\n      decoration: BoxDecoration(\n        color: AppColors.surfaceOf(context),'),
            ('        border: Border.all(color: AppColors.border, width: 0.5),',
             '        border: Border.all(color: AppColors.borderOf(context), width: 0.5),'),
            # recordItemCard - needs context
            ('  static Widget recordItemCard({required Widget child}) {\n    return Container(\n      margin: const EdgeInsets.only(bottom: 8),\n      padding: const EdgeInsets.all(12),\n      decoration: BoxDecoration(\n        color: Colors.white,\n        borderRadius: BorderRadius.circular(10),\n        border: Border.all(color: AppColors.border, width: 0.5),',
             '  static Widget recordItemCard({required Widget child, required BuildContext context}) {\n    return Container(\n      margin: const EdgeInsets.only(bottom: 8),\n      padding: const EdgeInsets.all(12),\n      decoration: BoxDecoration(\n        color: AppColors.surfaceOf(context),\n        borderRadius: BorderRadius.circular(10),\n        border: Border.all(color: AppColors.borderOf(context), width: 0.5),'),
            # settingsRowCard - needs context
            ('  static Widget settingsRowCard({\n    required Widget child,\n    EdgeInsetsGeometry? padding,\n  }) {\n    return Container(\n      margin: const EdgeInsets.only(bottom: 8),\n      padding: padding ?? const EdgeInsets.symmetric(horizontal: 4, vertical: 0),\n      decoration: BoxDecoration(\n        color: Colors.white,\n        borderRadius: BorderRadius.circular(10),\n        border: Border.all(color: AppColors.border, width: 0.5),',
             '  static Widget settingsRowCard({\n    required Widget child,\n    required BuildContext context,\n    EdgeInsetsGeometry? padding,\n  }) {\n    return Container(\n      margin: const EdgeInsets.only(bottom: 8),\n      padding: padding ?? const EdgeInsets.symmetric(horizontal: 4, vertical: 0),\n      decoration: BoxDecoration(\n        color: AppColors.surfaceOf(context),\n        borderRadius: BorderRadius.circular(10),\n        border: Border.all(color: AppColors.borderOf(context), width: 0.5),'),
            # profileAppBar
            ('  static AppBar profileAppBar(String title) {\n    return AppBar(\n      title: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),\n      backgroundColor: Colors.white,\n      foregroundColor: AppColors.textPrimary,',
             '  static AppBar profileAppBar(String title, {BuildContext? context}) {\n    return AppBar(\n      title: Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),\n      backgroundColor: context != null ? AppColors.surfaceOf(context) : Colors.white,\n      foregroundColor: context != null ? AppColors.textPrimaryOf(context) : AppColors.textPrimary,'),
            # dobPickerRow
            ('    return Material(\n      color: Colors.white,\n      borderRadius: BorderRadius.circular(10),',
             '    return Material(\n      color: AppColors.surfaceOf(context),\n      borderRadius: BorderRadius.circular(10),'),
            # In dobPickerRow the border also needs context
            ('            border: Border.all(color: AppColors.border),',
             '            border: Border.all(color: AppColors.borderOf(context)),'),
            # Static text colors in dobPickerRow - replace remaining AppColors.textSecondary
            ("style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),",
             "style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),"),
            ("style: GoogleFonts.inter(fontSize: 15, color: AppColors.textPrimary),",
             "style: GoogleFonts.inter(fontSize: 15, color: AppColors.textPrimaryOf(context)),"),
            ('Icon(Icons.calendar_today_outlined, color: AppColors.textSecondary, size: 20)',
             'Icon(Icons.calendar_today_outlined, color: AppColors.textSecondaryOf(context), size: 20)'),
        ],
    ),

    # ----- profile_edit_widgets.dart -----
    (
        r'c:/doctor/doctor/lib/features/patient/profile/widgets/profile_edit_widgets.dart',
        [
            # fillColor: editing ? Colors.white : AppColors.cardBackground
            ('fillColor: editing ? Colors.white : AppColors.cardBackground,',
             'fillColor: editing ? AppColors.surfaceOf(context) : AppColors.cardBgOf(context),'),
        ],
    ),

    # ----- doctor patient_filters_bar.dart -----
    (
        r'c:/doctor/doctor/lib/features/doctor/patients/widgets/patient_filters_bar.dart',
        [
            ('fillColor: AppColors.cardBackground,',
             'fillColor: AppColors.cardBgOf(context),'),
        ],
    ),

    # ----- location_dropdown_fields.dart -----
    (
        r'c:/doctor/doctor/lib/widgets/location_dropdown_fields.dart',
        [
            ('fillColor: AppColors.cardBackground,',
             'fillColor: AppColors.cardBgOf(context),'),
        ],
    ),

    # ----- specialization_selector.dart -----
    (
        r'c:/doctor/doctor/lib/widgets/specialization_selector.dart',
        [
            ('fillColor: Colors.grey.shade50,',
             'fillColor: AppColors.cardBgOf(context),'),
            ('style: TextStyle(fontSize: 12, color: Colors.grey.shade600),',
             'style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(context)),'),
            ('style: TextStyle(color: Colors.grey.shade600),',
             'style: TextStyle(color: AppColors.textSecondaryOf(context)),'),
            ('style: TextStyle(fontSize: 12, color: Colors.grey.shade500),',
             'style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(context)),'),
        ],
    ),

    # ----- prescription_rx_shared.dart -----
    (
        r'c:/doctor/doctor/lib/features/doctor/clinical/prescription/prescription_rx_shared.dart',
        [
            ('fillColor: Color(0xFFF9FAFB),',
             'fillColor: AppColors.cardBgOf(context),'),
        ],
    ),

    # ----- prescription_form_sections.dart -----
    (
        r'c:/doctor/doctor/lib/features/doctor/clinical/prescription/widgets/prescription_form_sections.dart',
        [
            ('fillColor: const Color(0xFFF9FAFB),',
             'fillColor: AppColors.cardBgOf(context),'),
            ('fillColor: const Color(0xFFFEF2F2),',
             "fillColor: AppColors.isDark(context) ? const Color(0xFF2D1515) : const Color(0xFFFEF2F2),"),
        ],
    ),

    # ----- doctor_lab_patients_screen.dart -----
    (
        r'c:/doctor/doctor/lib/features/doctor/lab/doctor_lab_patients_screen.dart',
        [
            ('fillColor: const Color(0xFFFAFBFC),',
             'fillColor: AppColors.cardBgOf(context),'),
        ],
    ),

    # ----- doctor_store_patients_screen.dart -----
    (
        r'c:/doctor/doctor/lib/features/doctor/pharmacy/doctor_store_patients_screen.dart',
        [
            ('fillColor: const Color(0xFFFAFBFC),',
             'fillColor: AppColors.cardBgOf(context),'),
        ],
    ),

    # ----- store_prescription_detail_screen.dart -----
    (
        r'c:/doctor/doctor/lib/features/pharmacy/screens/store_prescription_detail_screen.dart',
        [
            ('fillColor: const Color(0xFFFAFBFC),',
             'fillColor: AppColors.cardBgOf(context),'),
        ],
    ),

    # ----- lab_data_section.dart -----
    (
        r'c:/doctor/doctor/lib/features/doctor/profile/sections/lab_data_section.dart',
        [
            ('fillColor: Colors.grey[100],',
             'fillColor: AppColors.cardBgOf(context),'),
        ],
    ),
]

def main():
    changed_files = []
    for filepath, pairs in REPLACEMENTS:
        if not os.path.exists(filepath):
            print(f"MISSING: {filepath}")
            continue
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        modified = content
        for old, new in pairs:
            if old in modified:
                modified = modified.replace(old, new)
            else:
                print(f"NOT FOUND in {os.path.basename(filepath)}: {old[:60]!r}")
        if modified != content:
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write(modified)
            changed_files.append(filepath)
            print(f"  Fixed: {os.path.basename(filepath)}")

    # Also fix the app_theme.dart: light theme fillColor should stay white (intentional),
    # but let's double-check it's fine.
    print(f"\nTotal files updated: {len(changed_files)}")

if __name__ == '__main__':
    main()
