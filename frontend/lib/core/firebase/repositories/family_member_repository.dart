
import '../../../features/patient/profile/models/patient_profile_models.dart';
import '../../supabase/repositories/supabase_family_member_repository.dart';

class FamilyMemberRepository {
  FamilyMemberRepository._();

  static final FamilyMemberRepository instance = FamilyMemberRepository._();

  Future<List<FamilyProfileMember>> fetchForPatient(String patientId) async {
    return SupabaseFamilyMemberRepository.instance.fetchForPatient(patientId);
  }

  Future<void> saveMember(String patientId, FamilyProfileMember member) async {
    return SupabaseFamilyMemberRepository.instance
        .saveMember(patientId, member);
  }

  Future<void> deleteMember(String memberId) async {
    return SupabaseFamilyMemberRepository.instance.deleteMember(memberId);
  }
}
