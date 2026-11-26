import '../../../features/doctor/clinical/models/clinical_models.dart';
import '../firestore_query_limits.dart';
import 'package:medibond/core/data/data_page.dart';
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

  Future<DataPage<PrescriptionDraft>> fetchForDoctor(
    String doctorId, {
    String? startAfter,
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

  Future<DataPage<PrescriptionDraft>> fetchForPatient(
    String patientId, {
    String? startAfter,
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

  Future<DataPage<PrescriptionDraft>> fetchForPatientForDoctor(
    String patientId, {
    String? startAfter,
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

  Future<DataPage<PrescriptionDraft>> fetchForDoctorAndPatient(
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

  Future<DataPage<PrescriptionDraft>> fetchForDoctorAndPatientForDoctor(
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
