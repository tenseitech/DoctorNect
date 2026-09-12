import os
import re

def main():
    lib_dir = 'c:/doctor/doctor/lib'
    
    # 1. Fix doctor_home_sections.dart backgrounds
    doctor_home = os.path.join(lib_dir, 'features/doctor/home/widgets/doctor_home_sections.dart')
    with open(doctor_home, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Fix _elevatedCard
    content = content.replace('static BoxDecoration _elevatedCard() {', 'static BoxDecoration _elevatedCard(BuildContext context) {')
    content = content.replace('color: Colors.white,', 'color: AppColors.surfaceOf(context),')
    content = content.replace('decoration: _elevatedCard(),', 'decoration: _elevatedCard(context),')
    
    # Fix _DoctorServiceTileState
    content = content.replace(': AppColors.white,\n            borderRadius', ': AppColors.surfaceOf(context),\n            borderRadius')
    
    with open(doctor_home, 'w', encoding='utf-8') as f:
        f.write(content)

    # 2. Fix patient services_section.dart
    patient_services = os.path.join(lib_dir, 'features/patient/home/widgets/services_section.dart')
    if os.path.exists(patient_services):
        with open(patient_services, 'r', encoding='utf-8') as f:
            content = f.read()
        content = content.replace(': AppColors.white,\n            borderRadius', ': AppColors.surfaceOf(context),\n            borderRadius')
        with open(patient_services, 'w', encoding='utf-8') as f:
            f.write(content)

    # 3. Replace all remaining AppColors.textPrimary and AppColors.textSecondary
    for root, _, files in os.walk(lib_dir):
        for file in files:
            if not file.endswith('.dart'): continue
            path = os.path.join(root, file)
            
            # Skip these
            if 'app_theme.dart' in path or 'adaptive_app_shell.dart' in path or 'app_colors.dart' in path or 'appointment_card_shared.dart' in path:
                continue
                
            with open(path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            modified = content
            # Replace textPrimary not followed by Of
            modified = re.sub(r'AppColors\.textPrimary(?!Of)', 'AppColors.textPrimaryOf(context)', modified)
            modified = re.sub(r'AppColors\.textSecondary(?!Of)', 'AppColors.textSecondaryOf(context)', modified)
            
            if modified != content:
                with open(path, 'w', encoding='utf-8') as f:
                    f.write(modified)
                    
    print("Done")

if __name__ == '__main__':
    main()
