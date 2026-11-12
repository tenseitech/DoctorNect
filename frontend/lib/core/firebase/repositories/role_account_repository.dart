import '../../enums/user_type.dart';
import '../../supabase/supabase_bootstrap.dart';
import 'doctor_account_repository.dart';

/// Shared admin-approval and provider lifecycle gate for all account roles.
class RoleAccountRepository {
  RoleAccountRepository._();

  static final RoleAccountRepository instance = RoleAccountRepository._();

  static const underReviewLoginMessage =
      'Your account is under review. Our team will verify it within 24–48 hours.';

  static const underReviewRegistrationMessage =
      'Thank you for registering. Our team will verify your account within 24–48 hours. You can sign in after approval.';

  Future<bool> isVerified(
    UserType role,
    String profileId, {
    bool preferCache = false,
  }) async {
    return switch (role) {
      UserType.superAdmin => true,
      UserType.doctor => await DoctorAccountRepository.instance.isVerified(
          profileId,
          preferCache: preferCache,
        ),
      UserType.patient => true,
      UserType.lab => true,
      UserType.medicalStore || UserType.medical => true,
      UserType.ambulance => true,
    };
  }

  Future<void> deactivateProvider({
    required UserType role,
    required String profileId,
    required String ownerUid,
  }) async {
    if (role == UserType.doctor) {
      await DoctorAccountRepository.instance.deactivate(
        doctorId: profileId,
        ownerUid: ownerUid,
      );
      return;
    }

    if (!SupabaseBootstrap.isReady) {
      throw StateError('Supabase is not available.');
    }
    await SupabaseBootstrap.client.rpc('deactivate_provider_profile');
  }

  Future<void> reactivateProvider({
    required UserType role,
    required String profileId,
    required String ownerUid,
  }) async {
    if (role == UserType.doctor) {
      await DoctorAccountRepository.instance.reactivate(
        doctorId: profileId,
        ownerUid: ownerUid,
      );
      return;
    }

    if (!SupabaseBootstrap.isReady) {
      throw StateError('Supabase is not available.');
    }
    await SupabaseBootstrap.client.rpc('reactivate_provider_profile');
  }
}

typedef RoleAccountFirestore = RoleAccountRepository;
