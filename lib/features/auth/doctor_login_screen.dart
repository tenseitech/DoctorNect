import 'package:flutter/material.dart';

import '../../core/enums/user_type.dart';
import '../../core/theme/app_colors.dart';
import 'doctor_registration_screen.dart';
import 'login_screen_base.dart';

class DoctorLoginScreen extends StatelessWidget {
  const DoctorLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LoginScreenBase(
      userType: UserType.doctor,
      accentColor: AppColors.doctorBlue,
      registerRoute: DoctorRegistrationScreen(),
      title: 'Doctor Login',
    );
  }
}
