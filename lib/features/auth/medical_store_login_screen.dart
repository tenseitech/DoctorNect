import 'package:flutter/material.dart';

import '../../core/enums/user_type.dart';
import '../../core/theme/app_colors.dart';
import 'login_screen_base.dart';
import 'medical_store_registration_screen.dart';

class MedicalStoreLoginScreen extends StatelessWidget {
  const MedicalStoreLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LoginScreenBase(
      userType: UserType.medicalStore,
      accentColor: AppColors.pharmacyGreen,
      registerRoute: const MedicalStoreRegistrationScreen(),
    );
  }
}
