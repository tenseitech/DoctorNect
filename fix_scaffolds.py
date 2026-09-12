"""
Fix Scaffold and page-level background colors to use AppColors.cardBgOf(context)
"""
import re, os

LIB = r'c:/doctor/doctor/lib'

TARGET_FILES = [
    'features/doctor/clinical/clinical_tools_shell.dart',
    'features/doctor/clinical/prescription/edit_prescription_screen.dart',
    'features/doctor/clinical/prescription/patient_prescription_history_screen.dart',
    'features/doctor/home/doctor_home_screen.dart',
    'features/doctor/appointments/filtered_appointments_screen.dart',
    'features/doctor/appointments/todays_appointments_screen.dart',
    'features/doctor/lab/doctor_lab_patients_screen.dart',
    'features/doctor/pharmacy/doctor_store_patients_screen.dart',
    'features/doctor/profile/widgets/profile_widgets.dart',
    'features/lab/screens/lab_all_patients_screen.dart',
    'features/pharmacy/widgets/pharmacy_nav_shell.dart',
    'features/auth/widgets/auth_login_page_shell.dart',
    'features/ambulance/ambulance_profile_screen.dart',
]

def main():
    count = 0
    for rel_path in TARGET_FILES:
        full_path = os.path.join(LIB, rel_path)
        if not os.path.exists(full_path):
            print(f"MISSING: {rel_path}")
            continue
        with open(full_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        modified = content
        # Replace hardcoded light Scaffold background colors
        modified = re.sub(
            r'backgroundColor:\s*const\s*Color\(0xFFF[0-9A-F]{5}\)',
            'backgroundColor: AppColors.cardBgOf(context)',
            modified
        )
        modified = re.sub(
            r'backgroundColor:\s*const\s*Color\(0xFFFEF2F2\)',
            'backgroundColor: AppColors.cardBgOf(context)',
            modified
        )
        
        if modified != content:
            with open(full_path, 'w', encoding='utf-8') as f:
                f.write(modified)
            count += 1
            print(f"Fixed: {rel_path}")
        else:
            print(f"No match: {rel_path}")

    print(f"\nTotal files updated: {count}")

if __name__ == '__main__':
    main()
