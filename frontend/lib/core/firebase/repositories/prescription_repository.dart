
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../features/doctor/clinical/models/clinical_models.dart';
import '../firestore_query_limits.dart';
import '../models/firestore_page.dart';
import '../../supabase/repositories/supabase_prescription_repository.dart';

class PrescriptionRepository {
  PrescriptionRepository._();

  static final PrescriptionRepository instance = PrescriptionRepository._();

  Future<void> save(
    PrescriptionDraft draft,
    String doctorId, {
    bool isNewRecord = false,
  }) async {
    return SupabasePrescriptionRepository.instance
        .save(draft, doctorId, isNewRecord: isNewRecord);
  }

  Future<FirestorePage<PrescriptionDraft>> fetchForDoctor(
    String doctorId, {
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = FirestoreQueryLimits.prescriptionsPage,
    bool preferCache = true,
  }) {
    return SupabasePrescriptionRepository.instance.fetchForDoctor(
      doctorId,
      startAfter: startAfter,
      limit: limit,
      preferCache: preferCache,
    );
  }

  Future<FirestorePage<PrescriptionDraft>> fetchForPatient(
    String patientId, {
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = FirestoreQueryLimits.prescriptionsPage,
    bool preferCache = true,
  }) {
    return SupabasePrescriptionRepository.instance.fetchForPatient(
      patientId,
      startAfter: startAfter,
      limit: limit,
      preferCache: preferCache,
    );
  }

  Future<FirestorePage<PrescriptionDraft>> fetchForPatientForDoctor(
    String patientId, {
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = FirestoreQueryLimits.prescriptionsPage,
    bool preferCache = true,
  }) async {
    return SupabasePrescriptionRepository.instance.fetchForPatientForDoctor(
      patientId,
      startAfter: startAfter,
      limit: limit,
      preferCache: preferCache,
    );
  }

  Future<FirestorePage<PrescriptionDraft>> fetchForDoctorAndPatient(
    String doctorId,
    String patientId, {
    int limit = FirestoreQueryLimits.prescriptionsPage,
    bool preferCache = true,
  }) {
    return SupabasePrescriptionRepository.instance.fetchForDoctorAndPatient(
      doctorId,
      patientId,
      limit: limit,
      preferCache: preferCache,
    );
  }

  Future<FirestorePage<PrescriptionDraft>> fetchForDoctorAndPatientForDoctor(
    String doctorId,
    String patientId, {
    int limit = FirestoreQueryLimits.prescriptionsPage,
    bool preferCache = true,
  }) async {
    return SupabasePrescriptionRepository.instance
        .fetchForDoctorAndPatientForDoctor(
      doctorId,
      patientId,
      limit: limit,
      preferCache: preferCache,
    );
  }
}
