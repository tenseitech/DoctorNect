import '../models/doctor_referral.dart';
import '../../supabase/repositories/supabase_referral_repository.dart';

class ReferralRepository {
  ReferralRepository._();

  static final ReferralRepository instance = ReferralRepository._();

  Future<void> save(DoctorReferral referral) async {
    return SupabaseReferralRepository.instance.save(referral);
  }

  Future<DoctorReferral?> fetchById(
    String referralId, {
    bool preferCache = true,
  }) async {
    return SupabaseReferralRepository.instance
        .fetchById(referralId, preferCache: preferCache);
  }

  Future<List<DoctorReferral>> fetchSentByDoctor(
    String doctorId, {
    bool preferCache = true,
  }) async {
    return SupabaseReferralRepository.instance
        .fetchSentByDoctor(doctorId, preferCache: preferCache);
  }

  Future<List<DoctorReferral>> fetchReceivedByDoctor(
    String doctorId, {
    bool preferCache = true,
  }) async {
    return SupabaseReferralRepository.instance
        .fetchReceivedByDoctor(doctorId, preferCache: preferCache);
  }
}
