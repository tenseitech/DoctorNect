import 'package:flutter/material.dart';

import '../../core/enums/user_type.dart';
import '../../core/theme/app_colors.dart';
import 'lab_registration_screen.dart';
import 'login_screen_base.dart';

class LabLoginScreen extends StatelessWidget {
  const LabLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LoginScreenBase(
      userType: UserType.lab,
      accentColor: AppColors.labPurple,
      title: 'Diagnostic Lab Login',
      registerRoute: LabRegistrationScreen(),
    );
  }
}
