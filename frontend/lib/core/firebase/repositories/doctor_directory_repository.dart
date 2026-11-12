import '../../../features/patient/models/patient_models.dart';
import '../../supabase/repositories/supabase_doctor_repository.dart';

class DoctorDirectoryRepository {
  DoctorDirectoryRepository._();

  static final DoctorDirectoryRepository instance =
      DoctorDirectoryRepository._();

  Future<List<DoctorListing>> fetchVerifiedDoctors() async {
    return fetchAllDoctors(verifiedOnly: true);
  }

  Future<List<DoctorListing>> fetchAllDoctors({
    bool verifiedOnly = true,
  }) async {
    return SupabaseDoctorRepository.instance
        .fetchAllDoctors(verifiedOnly: verifiedOnly);
  }

  Stream<List<DoctorListing>> streamAllDoctors({bool verifiedOnly = true}) {
    return SupabaseDoctorRepository.instance
        .streamAllDoctors(verifiedOnly: verifiedOnly);
  }

  Future<bool> isDoctorVerified(
    String doctorId, {
    String? ownerUid,
    bool preferCache = false,
  }) async {
    return SupabaseDoctorRepository.instance.isDoctorVerified(
      doctorId,
      preferCache: preferCache,
    );
  }
}
