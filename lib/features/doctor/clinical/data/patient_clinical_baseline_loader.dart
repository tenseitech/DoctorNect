import '../../../../core/firebase/firestore_service.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/session/doctor_session.dart';
import '../models/clinical_models.dart';
import 'clinical_prescription_store.dart';

/// Loads stable patient clinical fields for follow-up visits (height, weight, allergies, etc.).
abstract final class PatientClinicalBaselineLoader {
  static bool hasBaselineData(PrescriptionDraft draft) {
    final v = draft.vitals;
    return v.heightCm.trim().isNotEmpty ||
        v.weightKg.trim().isNotEmpty ||
        v.bloodPressure.trim().isNotEmpty ||
        v.temperature.trim().isNotEmpty ||
        v.pulse.trim().isNotEmpty ||
        v.spo2.trim().isNotEmpty ||
        v.respiratoryRate.trim().isNotEmpty ||
        draft.pastHistory.trim().isNotEmpty ||
        draft.allergies.trim().isNotEmpty ||
        draft.generalExamination.trim().isNotEmpty;
  }

  /// Returns the most recent saved prescription that contains baseline data.
  static PrescriptionDraft? latestBaselineDraft(String patientId) {
    for (final draft
        in ClinicalPrescriptionStore.instance.forPatient(patientId)) {
      if (hasBaselineData(draft)) return draft;
    }
    return null;
  }

  static Future<PrescriptionDraft?> fetchLatestBaselineDraft(
      String patientId) async {
    if (patientId.isEmpty) return null;
    try {
      final doctorId = DoctorSession.loggedInDoctorId;
      if (doctorId.isNotEmpty) {
        if (!await FirestoreService.instance.patientProfile
            .isPatientSharingClinicalDataWithDoctors(
          patientId,
          preferCache: false,
        )) {
          return null;
        }

        final page = await FirestoreService.instance.prescription
            .fetchForDoctorAndPatientForDoctor(
          doctorId,
          patientId,
          preferCache: false,
        );
        for (final draft in page.items) {
          if (hasBaselineData(draft)) return draft;
        }
        return null;
      }

      await ClinicalPrescriptionStore.instance.refreshForPatient(
        patientId,
        preferCache: false,
      );
      return latestBaselineDraft(patientId);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
            'PatientClinicalBaselineLoader.fetchLatestBaselineDraft failed: $e\n$st');
      }
      return null;
    }
  }

  static Future<String?> fetchProfileAllergiesText(String patientId) async {
    if (patientId.isEmpty) return null;
    if (!await FirestoreService.instance.patientProfile
        .isPatientSharingClinicalDataWithDoctors(
      patientId,
    )) {
      return null;
    }
    final data = await FirestoreService.instance.patientProfile
        .fetchPatientDocumentForDoctor(patientId);
    if (data == null) return null;
    final list = (data['allergies'] as List<dynamic>? ?? const [])
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (list.isEmpty) return null;
    return list.join(', ');
  }

  static void applyBaseline({
    required PrescriptionDraft target,
    required PrescriptionDraft source,
    required void Function(String field, String value) setFieldIfEmpty,
  }) {
    final v = source.vitals;
    setFieldIfEmpty('heightCm', v.heightCm);
    setFieldIfEmpty('weightKg', v.weightKg);
    setFieldIfEmpty('bloodPressure', v.bloodPressure);
    setFieldIfEmpty('temperature', v.temperature);
    setFieldIfEmpty('pulse', v.pulse);
    setFieldIfEmpty('spo2', v.spo2);
    setFieldIfEmpty('respiratoryRate', v.respiratoryRate);
    setFieldIfEmpty('generalExamination', source.generalExamination);
    setFieldIfEmpty('pastHistory', source.pastHistory);
    setFieldIfEmpty('allergies', source.allergies);
  }
}
