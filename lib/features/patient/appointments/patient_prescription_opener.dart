import '../../../core/firebase/firestore_service.dart';
import 'package:flutter/material.dart';

import '../../../core/session/patient_session.dart';
import '../../doctor/clinical/data/clinical_prescription_store.dart';
import '../../doctor/clinical/models/clinical_models.dart';
import '../../doctor/clinical/prescription/prescription_preview_modal.dart';
import 'models/patient_appointment_models.dart';

abstract final class PatientPrescriptionOpener {
  static Future<PrescriptionDraft?> loadDraft(PatientAppointment appointment) async {
    final patientId = PatientSession.loggedInPatientId;
    if (patientId.isEmpty) return null;

    final page = await FirestoreService.instance.prescription.fetchForPatient(
      patientId,
      preferCache: false,
    );
    ClinicalPrescriptionStore.instance.mergeFirestoreRecords(page.items);
    return _matchDraft(
      appointment,
      ClinicalPrescriptionStore.instance.forPatient(patientId),
    );
  }

  static Future<void> open(
    BuildContext context,
    PatientAppointment appointment,
  ) async {
    if (PatientSession.loggedInPatientId.isEmpty) {
      _snack(context, 'Please sign in again.');
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      final draft = await loadDraft(appointment);

      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      if (draft == null) {
        _snack(
          context,
          'Prescription not found. Check My Prescriptions in Profile.',
        );
        return;
      }

      PrescriptionPreviewModal.show(context, draft: draft);
    } catch (_) {
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      _snack(context, 'Could not load prescription. Try again.');
    }
  }

  static PrescriptionDraft? _matchDraft(
    PatientAppointment appointment,
    List<PrescriptionDraft> drafts,
  ) {
    if (drafts.isEmpty) return null;

    for (final draft in drafts) {
      final linkedAppointmentId = draft.patient.appointmentId;
      if (linkedAppointmentId != null &&
          (linkedAppointmentId == appointment.id ||
              linkedAppointmentId == appointment.appointmentId)) {
        return draft;
      }
    }

    final diagnosis = appointment.diagnosis?.trim();
    if (diagnosis != null && diagnosis.isNotEmpty) {
      for (final draft in drafts) {
        final primary = draft.primaryDiagnosis.trim();
        if (primary == diagnosis || primary.contains(diagnosis) || diagnosis.contains(primary)) {
          return draft;
        }
      }
    }

    for (final draft in drafts) {
      if (_sameDay(draft.prescriptionDate, appointment.dateTime)) {
        return draft;
      }
    }

    return drafts.first;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
