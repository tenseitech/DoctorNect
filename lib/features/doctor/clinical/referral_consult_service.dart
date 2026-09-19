import '../../../core/firebase/firestore_service.dart';
import 'package:flutter/material.dart';

import '../../../core/firebase/models/doctor_referral.dart';
import '../../../core/session/doctor_session.dart';
import 'clinical_tools_shell.dart';
import 'models/clinical_models.dart';

/// Opens a referred registered patient for the receiving specialist (Doctor B).
abstract final class ReferralConsultService {
  /// Self-grants care-team access when [patients/{id}/doctor_links/{B}] exists (C1/C2).
  static Future<bool> prepareReceivingDoctorAccess(
      DoctorReferral referral) async {
    if (!PatientProfileRepository.isRegisteredPatientId(referral.patientId)) {
      return false;
    }

    final doctorId = DoctorSession.loggedInDoctorId;
    if (doctorId.isEmpty || referral.toDoctorId != doctorId) {
      return false;
    }

    final granted = await FirestoreService.instance.patientProfile
        .grantDoctorCareTeamAccess(
      patientId: referral.patientId,
      doctorId: doctorId,
    );
    if (!granted) return false;

    final profile = await FirestoreService.instance.patientProfile
        .fetchPatientDocumentForDoctor(
      referral.patientId,
      preferCache: false,
    );
    if (profile == null) return false;
    return true;
  }

  static Future<void> openIncomingConsult(
    BuildContext context,
    DoctorReferral referral,
  ) async {
    if (!PatientProfileRepository.isRegisteredPatientId(referral.patientId)) {
      _snack(
        context,
        'This referral is not linked to a registered patient profile.',
      );
      return;
    }

    final doctorId = DoctorSession.loggedInDoctorId;
    if (doctorId.isEmpty || referral.toDoctorId != doctorId) {
      _snack(context, 'Only the receiving specialist can open this referral.');
      return;
    }

    final ok = await prepareReceivingDoctorAccess(referral);
    if (!context.mounted) return;
    if (!ok) {
      _snack(
        context,
        'Could not access this patient profile. Ask the referring doctor to resend the referral.',
      );
      return;
    }

    await ClinicalToolsShell.open(
      context,
      patient: PatientClinicalContext(
        patientName: referral.patientName,
        age: referral.patientAge,
        patientId: referral.patientId,
        appointmentId: referral.appointmentId,
      ),
    );
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
