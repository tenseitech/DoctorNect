import '../enums/user_type.dart';

/// Explicit lifecycle stages for professional/service account verification.
enum VerificationStage {
  /// Account created; profile information not yet filled.
  registered('registered'),

  /// Profile partially filled or missing required documents.
  profileIncomplete('profile_incomplete'),

  /// All required profile details and documents provided; ready to submit or under review.
  submittedForVerification('submitted_for_verification'),

  /// Super Admin approved; account is fully active and operational features unlocked.
  verified('verified'),

  /// Super Admin requested corrections with a specific reason.
  revisionRequested('revision_requested'),

  /// Account rejected.
  rejected('rejected');

  const VerificationStage(this.wireValue);

  final String wireValue;

  static VerificationStage fromString(String? value) {
    if (value == null) return VerificationStage.registered;
    return switch (value.trim().toLowerCase()) {
      'verified' || 'approved' => VerificationStage.verified,
      'submitted_for_verification' || 'pending_review' =>
        VerificationStage.submittedForVerification,
      'revision_requested' => VerificationStage.revisionRequested,
      'rejected' => VerificationStage.rejected,
      'profile_incomplete' => VerificationStage.profileIncomplete,
      _ => VerificationStage.registered,
    };
  }

  bool get isVerified => this == VerificationStage.verified;
  bool get isPending => this == VerificationStage.submittedForVerification;
  bool get isRevisionRequested => this == VerificationStage.revisionRequested;
  bool get isIncomplete =>
      this == VerificationStage.registered ||
      this == VerificationStage.profileIncomplete;

  String get displayLabel => switch (this) {
        VerificationStage.registered => 'Registration Complete',
        VerificationStage.profileIncomplete => 'Profile Incomplete',
        VerificationStage.submittedForVerification => 'Under Review',
        VerificationStage.verified => 'Verified',
        VerificationStage.revisionRequested => 'Action Required',
        VerificationStage.rejected => 'Rejected',
      };
}

/// Document or credential requirement definition.
class VerificationRequirementItem {
  const VerificationRequirementItem({
    required this.key,
    required this.label,
    required this.description,
    this.isDocument = false,
  });

  final String key;
  final String label;
  final String description;
  final bool isDocument;
}

/// Configurable verification requirements per role.
/// Additional requirements can be added here without rewriting authentication or verification flows.
abstract final class VerificationRequirementsConfig {
  static List<VerificationRequirementItem> requirementsForRole(UserType role) {
    return switch (role) {
      UserType.doctor => const [
          VerificationRequirementItem(
            key: 'qualification',
            label: 'Medical Degree / Qualification',
            description: 'Recognized medical degree (e.g., MBBS, MD, MS)',
          ),
          VerificationRequirementItem(
            key: 'councilNumber',
            label: 'Medical Registration Number',
            description: 'State or National Medical Council registration number',
          ),
          VerificationRequirementItem(
            key: 'stateCouncil',
            label: 'Registration Authority',
            description: 'Issuing State / National Medical Council',
          ),
          VerificationRequirementItem(
            key: 'registrationCertificate',
            label: 'Registration Certificate',
            description: 'Official council registration document or certificate',
            isDocument: true,
          ),
          VerificationRequirementItem(
            key: 'idProof',
            label: 'Identity Proof',
            description: 'Government-issued photo identification',
            isDocument: true,
          ),
        ],
      UserType.medicalStore => const [
          VerificationRequirementItem(
            key: 'storeName',
            label: 'Pharmacy / Store Name',
            description: 'Registered business name of the medical store',
          ),
          VerificationRequirementItem(
            key: 'drugLicenseNumber',
            label: 'Drug License Number',
            description: 'Valid Form 20/21 drug retail license number',
          ),
          VerificationRequirementItem(
            key: 'ownerName',
            label: 'Owner / Pharmacist Name',
            description: 'Name of the licensed pharmacist or owner',
          ),
          VerificationRequirementItem(
            key: 'address',
            label: 'Physical Store Address',
            description: 'Complete commercial address with PIN code',
          ),
        ],
      UserType.lab => const [
          VerificationRequirementItem(
            key: 'labName',
            label: 'Diagnostic Lab Name',
            description: 'Registered diagnostic centre or laboratory name',
          ),
          VerificationRequirementItem(
            key: 'licenseNumber',
            label: 'Clinical Establishment License',
            description: 'Valid diagnostic/pathology registration number',
          ),
          VerificationRequirementItem(
            key: 'address',
            label: 'Lab Location & Address',
            description: 'Complete laboratory facility address with PIN code',
          ),
        ],
      UserType.ambulance => const [
          VerificationRequirementItem(
            key: 'serviceName',
            label: 'Ambulance Service Name',
            description: 'Fleet or emergency transport service name',
          ),
          VerificationRequirementItem(
            key: 'vehicleNumber',
            label: 'Vehicle Registration Number',
            description: 'Commercial motor vehicle registration number',
          ),
          VerificationRequirementItem(
            key: 'driverName',
            label: 'Driver / Operator Name',
            description: 'Name of the designated ambulance driver',
          ),
          VerificationRequirementItem(
            key: 'licenseNumber',
            label: 'Driver License Number',
            description: 'Commercial driving license number',
          ),
        ],
      _ => const [],
    };
  }

  /// Evaluates whether the given profile document data meets all requirements for the role.
  static bool isRequirementsMet(UserType role, Map<String, dynamic>? data) {
    if (data == null) return false;
    final items = requirementsForRole(role);
    for (final item in items) {
      final value = data[item.key];
      if (value == null) return false;
      if (value is String && value.trim().isEmpty) return false;
      if (value is Map && value.isEmpty) return false;
      if (value is List && value.isEmpty) return false;
    }
    return true;
  }
}
