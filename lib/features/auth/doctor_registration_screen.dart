import 'package:flutter/material.dart';

import '../../core/auth/registration_credentials.dart';
import '../../core/auth/registration_otp_service.dart';
import '../../core/enums/user_type.dart';
import '../../core/firebase/firebase_auth_service.dart';
import '../../core/firebase/firebase_bootstrap.dart';
import '../../core/invite/pending_pharmacy_invite_store.dart';
import '../../core/notifications/app_toast.dart';
import '../../core/session/doctor_session.dart';
import '../../core/theme/app_colors.dart';
import '../../core/validators/form_validators.dart';
import '../dashboard/dashboard_shell.dart';
import 'widgets/simple_role_registration_form.dart';

class DoctorRegistrationScreen extends StatelessWidget {
  const DoctorRegistrationScreen({super.key, this.preVerifiedMobile});

  final String? preVerifiedMobile;

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
    final doctorId = 'd${DateTime.now().millisecondsSinceEpoch}';
    final invitedStoreId = PendingPharmacyInviteStore.pendingStoreId;

    final roleData = {
      'doctorId': doctorId,
      'name': name,
      'qualification': qualification,
      'mobile': mobile,
      'email': email,
      'verified': false,
      'verificationStatus': 'registered',
      'status': 'pending_review',
      'kycSubmitted': false,
      'profileCompleted': false,
      'clinicName': '$name Clinic',
      'rating': 0,
      'reviewCount': 0,
      if (invitedStoreId != null && invitedStoreId.isNotEmpty)
        'invitedByStoreId': invitedStoreId,
    };

    final result = await FirebaseAuthService.instance.registerProfile(
      role: UserType.doctor,
      email: email,
      password: password,
      profileId: doctorId,
      displayName: name,
      mobile: mobile,
      otpVerificationSessionId: RegistrationOtpService.verificationSessionId,
      roleData: roleData,
    );

    if (!context.mounted) return;
    if (!result.success) {
      AppToast.info(context, result.message ?? 'Registration failed');
      return;
    }

    DoctorSession.setDoctor(id: doctorId, name: name);
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const DashboardShell(userType: UserType.doctor),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SimpleRoleRegistrationForm(
      role: UserType.doctor,
      accentColor: AppColors.doctorBlue,
      appBarTitle: 'Doctor Registration',
      welcomeTitle: 'Join as Doctor',
      subtitle: 'Quick signup — complete your full profile after verification',
      icon: Icons.medical_services_outlined,
      preVerifiedMobile: preVerifiedMobile,
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
