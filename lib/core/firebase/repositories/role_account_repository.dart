import '../../enums/user_type.dart';
import 'doctor_account_repository.dart';

/// Shared admin-approval gate for all email/password account roles.
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
      UserType.doctor =>
        await DoctorAccountRepository.instance.isVerified(profileId, preferCache: preferCache),
      UserType.patient => true,
      UserType.lab => true,
      UserType.medicalStore => true,
      UserType.ambulance => true,
    };
  }
}

typedef RoleAccountFirestore = RoleAccountRepository;

