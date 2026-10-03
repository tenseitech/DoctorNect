import 'package:flutter/material.dart';

import '../../core/auth/demo_auth_config.dart';
import '../../core/auth/registration_credentials.dart';
import '../../core/auth/registration_otp_service.dart';
import '../../core/auth/verification_lifecycle.dart';
import '../../core/enums/user_type.dart';
import '../../core/firebase/firebase_auth_service.dart';
import '../../core/firebase/firebase_bootstrap.dart';
import '../../core/invite/pending_pharmacy_invite_store.dart';
import '../../core/notifications/app_toast.dart';
import '../../core/session/doctor_session.dart';
import '../../core/theme/app_colors.dart';
import '../../core/validators/form_validators.dart';
import '../../core/supabase/supabase_bootstrap.dart';
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
    List<String>? degrees,
    List<String>? specializations,
  }) async {
    if (!FirebaseBootstrap.isReady) {
      AppToast.info(context, 'Firebase is not available. Please try again.');
      return;
    }

    final mobileDigits = FormValidators.mobileDigits(mobile) ?? '';
    final isDemoDoctor = DemoAuthConfig.isDemoDoctorPhone(mobileDigits);
    final email = RegistrationCredentials.emailForMobile(mobileDigits);
    final password = RegistrationCredentials.generatePassword();
    final doctorId = await SupabaseBootstrap.resolveRegistrationProfileId(
      role: 'doctor',
      defaultClientId: 'd${DateTime.now().millisecondsSinceEpoch}',
    );
    final invitedStoreId = PendingPharmacyInviteStore.pendingStoreId;

    final validDegrees = degrees != null && degrees.isNotEmpty
        ? degrees
        : (qualification.isNotEmpty ? [qualification] : <String>['MBBS']);
    final validSpecializations =
        specializations != null && specializations.isNotEmpty
            ? specializations
            : <String>['General Physician'];
    final primarySpec = validSpecializations.first;
    final primaryQual = validDegrees.join(', ');

    final roleData = {
      'doctorId': doctorId,
      'name': name,
      'qualification': primaryQual,
      'degree': validDegrees.first,
      'degrees': validDegrees,
      'specialization': primarySpec,
      'specializations': validSpecializations,
      'mobile': mobile,
      'email': email,
      'verified': isDemoDoctor ? true : false,
      'verificationStatus': isDemoDoctor ? 'verified' : 'profile_incomplete',
      'status': isDemoDoctor ? 'approved' : 'pending_review',
      'kycSubmitted': isDemoDoctor ? true : false,
      'profileCompleted': isDemoDoctor ? true : false,
      'clinicName': '$name Clinic',
      'rating': isDemoDoctor ? 4.9 : 0,
      'reviewCount': isDemoDoctor ? 24 : 0,
      if (isDemoDoctor) ...{
        'councilNumber': 'MCI-7666892394',
        'stateCouncil': 'Maharashtra Medical Council',
        'registrationYear': 2016,
        'yearsExperience': 10,
        'registrationCertificate':
            'https://storage.googleapis.com/demo/medical_council_cert.pdf',
        'idProof': 'https://storage.googleapis.com/demo/doctor_id_proof.pdf',
      },
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
    RoleVerificationController.instance.setRoleState(
      UserType.doctor,
      stage: isDemoDoctor
          ? VerificationStage.verified
          : VerificationStage.profileIncomplete,
    );
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
      onSubmit: ({
        required name,
        required qualification,
        required mobile,
        degrees,
        specializations,
      }) =>
          _register(
        context,
        name: name,
        qualification: qualification,
        mobile: mobile,
        degrees: degrees,
        specializations: specializations,
      ),
    );
  }
}
