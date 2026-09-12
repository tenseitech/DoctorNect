import 'package:flutter/material.dart';

import '../../features/auth/doctor_login_screen.dart';
import '../../features/auth/lab_login_screen.dart';
import '../../features/auth/medical_store_login_screen.dart';
import '../../features/auth/patient_login_screen.dart';
import '../../features/ambulance/ambulance_login_screen.dart';
import 'pending_doctor_invite_store.dart';
import 'pending_lab_invite_store.dart';
import 'pending_pharmacy_invite_store.dart';

/// Resolves invite deep links to the correct role-specific login screen.
abstract final class InviteDeepLinkResolver {
  static Widget? loginScreenFromPendingInvite() {
    if (PendingPharmacyInviteStore.pendingStoreId != null) {
      return const DoctorLoginScreen();
    }

    if (PendingLabInviteStore.pendingLabId != null) {
      if (PendingLabInviteStore.pendingRole == 'doctor') {
        return const DoctorLoginScreen();
      }
      return const LabLoginScreen();
    }

    final role = PendingDoctorInviteStore.pendingRole;
    final hasDoctorInvite = PendingDoctorInviteStore.pendingDoctorId != null;

    if (hasDoctorInvite || role != null) {
      return switch (role) {
        'pharmacy' => const MedicalStoreLoginScreen(),
        'lab' => const LabLoginScreen(),
        'doctor' => const DoctorLoginScreen(),
        'ambulance' => const AmbulanceLoginScreen(),
        _ => const PatientLoginScreen(),
      };
    }

    return null;
  }
}
