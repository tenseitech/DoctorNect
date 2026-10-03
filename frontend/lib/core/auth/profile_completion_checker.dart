import '../enums/user_type.dart';
import 'verification_lifecycle.dart';

/// Evaluates profile completion by delegating directly to [VerificationRequirementsConfig],
/// which is the single source of truth across roles.
abstract final class ProfileCompletionChecker {
  static bool isDoctorDocComplete(Map<String, dynamic>? data) {
    return VerificationRequirementsConfig.isComplete(UserType.doctor, data);
  }

  static bool isPharmacyDocComplete(Map<String, dynamic>? data) {
    return VerificationRequirementsConfig.isComplete(
      UserType.medicalStore,
      data,
    );
  }

  static bool isLabDocComplete(Map<String, dynamic>? data) {
    return VerificationRequirementsConfig.isComplete(UserType.lab, data);
  }

  static bool isAmbulanceDocComplete(Map<String, dynamic>? data) {
    return VerificationRequirementsConfig.isComplete(UserType.ambulance, data);
  }
}
