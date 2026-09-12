import 'package:flutter/material.dart';

import '../../core/enums/user_type.dart';
import '../../core/theme/app_colors.dart';
import 'login_screen_base.dart';
import 'patient_registration_screen.dart';

class PatientLoginScreen extends StatelessWidget {
  const PatientLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LoginScreenBase(
      userType: UserType.patient,
      accentColor: AppColors.patientTeal,
      registerRoute: const PatientRegistrationScreen(),
    );
  }
}
