import 'package:flutter/material.dart';

import '../../core/enums/user_type.dart';
import '../../core/session/doctor_session.dart';
import '../doctor/verification/doctor_verification_gate.dart';
import '../patient/patient_shell.dart';
import '../pharmacy/medical_store_shell.dart';
import '../lab/lab_shell.dart';
import '../admin/super_admin_verification_screen.dart';

class DashboardShell extends StatelessWidget {
  const DashboardShell({super.key, required this.userType});

  final UserType userType;

  @override
  Widget build(BuildContext context) {
    return _shellFor(userType);
  }

  Widget _shellFor(UserType userType) {
    if (userType == UserType.superAdmin) {
      return const SuperAdminVerificationScreen();
    }
    if (userType.isDoctor) {
      return DoctorVerificationGate(doctorId: DoctorSession.loggedInDoctorId);
    }
    if (userType.isMedicalStore) {
      return const MedicalStoreShell();
    }
    if (userType.isLab) {
      return const LabShell();
    }
    return const PatientShell();
  }
}
