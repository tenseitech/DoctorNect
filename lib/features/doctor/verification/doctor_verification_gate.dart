import '../../../core/firebase/firestore_service.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../doctor_shell.dart';

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
            child: CircularProgressIndicator(color: AppColors.doctorBlue)),
      );
    }

    return StreamBuilder<bool>(
      stream:
          FirestoreService.instance.doctorVerification.watchVerified(doctorId),
      builder: (context, snapshot) {
        final verified = snapshot.data ?? false;
        return verifiedChildOverride ??
            DoctorShell(verificationPending: !verified);
      },
    );
  }
}
