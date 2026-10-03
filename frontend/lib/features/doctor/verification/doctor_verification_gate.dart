import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/auth/demo_auth_config.dart';
import '../../../core/auth/verification_lifecycle.dart';
import '../../../core/enums/user_type.dart';
import '../../../core/firebase/firebase_bootstrap.dart';
import '../../../core/firebase/firestore_service.dart';

import 'package:flutter/material.dart';

import '../../../core/session/doctor_session.dart';
import '../../../core/theme/app_colors.dart';
import '../doctor_shell.dart';
import '../profile/data/doctor_profile_store.dart';

/// Shows [DoctorShell] for all signed-in doctors.
/// Data tabs gate on profile completion; live data also requires admin verification.
class DoctorVerificationGate extends StatelessWidget {
  const DoctorVerificationGate({
    super.key,
    required this.doctorId,
    @visibleForTesting this.verifiedChildOverride,
  });

  final String doctorId;

  @visibleForTesting
  final Widget? verifiedChildOverride;

  @override
  Widget build(BuildContext context) {
    if (doctorId.isEmpty) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.doctorBlue),
        ),
      );
    }

    final authPhone = FirebaseBootstrap.isReady
        ? FirebaseAuth.instance.currentUser?.phoneNumber
        : null;

    final isDemoDoc = DemoAuthConfig.isDemoDoctorPhone(doctorId) ||
        doctorId.contains(DemoAuthConfig.demoDoctorPhone) ||
        DemoAuthConfig.isDemoDoctorPhone(
          DoctorProfileStore.instance.profile.mobile,
        ) ||
        DemoAuthConfig.isDemoDoctorPhone(DoctorSession.loggedInDoctorId) ||
        DoctorSession.loggedInDoctorId.contains(
          DemoAuthConfig.demoDoctorPhone,
        ) ||
        DemoAuthConfig.isDemoDoctorPhone(authPhone);

    if (isDemoDoc) {
      return verifiedChildOverride ??
          const DoctorShell(verificationPending: false);
    }

    return ListenableBuilder(
      listenable: Listenable.merge([
        RoleVerificationController.instance,
        DoctorProfileStore.instance,
      ]),
      builder: (context, _) {
        return StreamBuilder<bool>(
          stream: FirestoreService.instance.doctorVerification.watchVerified(
            doctorId,
          ),
          builder: (context, snapshot) {
            final streamVerified = snapshot.data ?? false;
            final controllerVerified =
                RoleVerificationController.instance.isVerified(UserType.doctor);
            final verified = streamVerified || controllerVerified;
            return verifiedChildOverride ??
                DoctorShell(verificationPending: !verified);
          },
        );
      },
    );
  }
}
