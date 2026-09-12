import 'package:flutter/material.dart';

import '../../core/auth/registration_credentials.dart';
import '../../core/auth/registration_otp_service.dart';
import '../../core/enums/user_type.dart';
import '../../core/firebase/firebase_auth_service.dart';
import '../../core/firebase/firebase_bootstrap.dart';
import '../../core/notifications/app_toast.dart';
import '../../core/session/lab_session.dart';
import '../../core/validators/form_validators.dart';
import '../dashboard/dashboard_shell.dart';
import 'widgets/simple_role_registration_form.dart';

class LabRegistrationScreen extends StatelessWidget {
  const LabRegistrationScreen({super.key});

  static const _accent = Color(0xFF8B5CF6);

  Future<void> _register(
    BuildContext context, {
    required String name,
    required String qualification,
    required String mobile,
  }) async {
    if (!FirebaseBootstrap.isReady) {
      AppToast.info(context, 'Firebase is not available. Please try again.');
      return;
    }

    final mobileDigits = FormValidators.mobileDigits(mobile) ?? '';
    final email = RegistrationCredentials.emailForMobile(mobileDigits);
    final password = RegistrationCredentials.generatePassword();
    final labId = 'lab${DateTime.now().millisecondsSinceEpoch}';

    final result = await FirebaseAuthService.instance.registerProfile(
      role: UserType.lab,
      email: email,
      password: password,
      profileId: labId,
      displayName: name,
      mobile: mobile,
      otpVerificationSessionId: RegistrationOtpService.verificationSessionId,
      roleData: {
        'labId': labId,
        'labName': '$name Lab',
        'name': '$name Lab',
        'ownerName': name,
        'qualification': qualification,
        'phone': mobile,
        'email': email,
        'verified': true,
        'status': 'approved',
        'profileCompleted': false,
      },
    );

    if (!context.mounted) return;
    if (!result.success) {
      AppToast.info(context, result.message ?? 'Registration failed');
      return;
    }

    LabSession.setLab(id: labId, name: name);
    AppToast.success(context, 'Account created! Complete your profile to access lab orders.');
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const DashboardShell(userType: UserType.lab),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SimpleRoleRegistrationForm(
      role: UserType.lab,
      accentColor: _accent,
      appBarTitle: 'Lab Registration',
      welcomeTitle: 'Join as Diagnostic Lab',
      subtitle: 'Quick signup — add lab details in your profile next',
      icon: Icons.biotech_outlined,
      nameLabel: 'Contact person name *',
      onSubmit: ({required name, required qualification, required mobile}) =>
          _register(
        context,
        name: name,
        qualification: qualification,
        mobile: mobile,
      ),
    );
  }
}
