import 'package:flutter/material.dart';

import '../../core/enums/user_type.dart';
import '../../core/session/ambulance_session.dart';
import '../../core/session/doctor_session.dart';
import '../ambulance/ambulance_shell.dart';
import '../ambulance/data/ambulance_store.dart';
import '../ambulance/models/ambulance_models.dart';
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
      final docId = DoctorSession.loggedInDoctorId.isNotEmpty
          ? DoctorSession.loggedInDoctorId
          : 'doc-new';
      return DoctorVerificationGate(doctorId: docId);
    }
    if (userType.isMedicalStore) {
      return const MedicalStoreShell();
    }
    if (userType.isLab) {
      return const LabShell();
    }
    if (userType.isAmbulance) {
      final ambId = AmbulanceSession.loggedInAmbulanceId.isNotEmpty
          ? AmbulanceSession.loggedInAmbulanceId
          : 'amb-new';
      final amb =
          AmbulanceStore.instance.findAmbulance(ambId) ??
          (AmbulanceStore.instance.registeredAmbulances.isNotEmpty
              ? AmbulanceStore.instance.registeredAmbulances.first
              : RegisteredAmbulance(
                  id: ambId,
                  serviceName: AmbulanceSession.loggedInServiceName.isNotEmpty
                      ? AmbulanceSession.loggedInServiceName
                      : 'Ambulance Service',
                  driverName: AmbulanceSession.loggedInDriverName.isNotEmpty
                      ? AmbulanceSession.loggedInDriverName
                      : '',
                  phone: '',
                  vehicleNumber: '',
                  city: '',
                  available: false,
                  verified: false,
                ));
      return AmbulanceShell(ambulance: amb);
    }
    return const PatientShell();
  }
}
