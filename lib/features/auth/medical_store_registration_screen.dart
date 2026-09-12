import 'package:flutter/material.dart';

import '../../core/auth/registration_credentials.dart';
import '../../core/auth/registration_otp_service.dart';
import '../../core/enums/user_type.dart';
import '../../core/firebase/firebase_auth_service.dart';
import '../../core/firebase/firebase_bootstrap.dart';
import '../../core/notifications/app_toast.dart';
import '../../core/session/medical_store_session.dart';
import '../../core/theme/app_colors.dart';
import '../../core/validators/form_validators.dart';
import '../dashboard/dashboard_shell.dart';
import '../pharmacy/data/medical_store_registry.dart';
import 'widgets/simple_role_registration_form.dart';

class MedicalStoreRegistrationScreen extends StatelessWidget {
  const MedicalStoreRegistrationScreen({super.key});

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
    final storeId = MedicalStoreRegistry.register(
      storeName: '$name Pharmacy',
      ownerName: name,
      address: '',
      drugLicenseNumber: '',
      phone: mobile,
      email: email,
    );

    final result = await FirebaseAuthService.instance.registerProfile(
      role: UserType.medicalStore,
      email: email,
      password: password,
      profileId: storeId,
      displayName: name,
      mobile: mobile,
      otpVerificationSessionId: RegistrationOtpService.verificationSessionId,
      roleData: {
        'storeId': storeId,
        'storeName': '$name Pharmacy',
        'name': '$name Pharmacy',
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

    MedicalStoreSession.setStore(id: storeId, name: name);
    AppToast.success(context, 'Account created! Complete your profile to access orders.');
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const DashboardShell(userType: UserType.medicalStore),
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SimpleRoleRegistrationForm(
      role: UserType.medicalStore,
      accentColor: AppColors.pharmacyGreen,
      appBarTitle: 'Pharmacy Registration',
      welcomeTitle: 'Join as Pharmacy',
      subtitle: 'Quick signup — add store details in your profile next',
      icon: Icons.local_pharmacy_outlined,
      nameLabel: 'Owner name *',
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
