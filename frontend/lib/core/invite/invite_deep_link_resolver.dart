import 'package:flutter/material.dart';

import '../enums/user_type.dart';
import '../../features/auth/unified_mobile_auth_screen.dart';
import 'pending_doctor_invite_store.dart';
import 'pending_lab_invite_store.dart';
import 'pending_pharmacy_invite_store.dart';

/// Resolves invite deep links to the unified mobile auth screen for the invited role.
abstract final class InviteDeepLinkResolver {
  static Widget? loginScreenFromPendingInvite() {
    final role = _roleFromPendingInvite();
    if (role == null) return null;
    return UnifiedMobileAuthScreen(role: role);
  }

  static UserType? _roleFromPendingInvite() {
    if (PendingPharmacyInviteStore.pendingStoreId != null) {
      return UserType.doctor;
    }

    if (PendingLabInviteStore.pendingLabId != null) {
      if (PendingLabInviteStore.pendingRole == 'doctor') {
        return UserType.doctor;
      }
      return UserType.lab;
    }

    final role = PendingDoctorInviteStore.pendingRole;
    final hasDoctorInvite = PendingDoctorInviteStore.pendingDoctorId != null;

    if (hasDoctorInvite || role != null) {
      return switch (role) {
        'pharmacy' => UserType.medicalStore,
        'lab' => UserType.lab,
        'doctor' => UserType.doctor,
        'ambulance' => UserType.ambulance,
        _ => UserType.patient,
      };
    }

    return null;
  }
}
