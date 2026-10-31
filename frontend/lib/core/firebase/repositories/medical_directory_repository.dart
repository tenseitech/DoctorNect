import 'package:cloud_firestore/cloud_firestore.dart';

import '../../supabase/repositories/supabase_medical_directory_repository.dart';
import '../firestore_query_limits.dart';
import '../models/doctor_medical_directory_entry.dart';
import '../models/firestore_page.dart';

class MedicalDirectoryRepository {
  MedicalDirectoryRepository._();

  static final MedicalDirectoryRepository instance =
      MedicalDirectoryRepository._();

  Future<void> save(DoctorMedicalDirectoryEntry entry) async {
    return SupabaseMedicalDirectoryRepository.instance.save(entry);
  }

  Future<void> update(DoctorMedicalDirectoryEntry entry) async {
    return SupabaseMedicalDirectoryRepository.instance.update(entry);
  }

  Future<void> delete(String entryId) async {
    return SupabaseMedicalDirectoryRepository.instance.delete(entryId);
  }

  Future<FirestorePage<DoctorMedicalDirectoryEntry>> fetchForDoctor(
    String doctorId, {
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = FirestoreQueryLimits.medicalDirectoryPage,
    bool preferCache = true,
  }) async {
    return SupabaseMedicalDirectoryRepository.instance.fetchForDoctor(
        doctorId,
        limit: limit,
      );
  }
}
