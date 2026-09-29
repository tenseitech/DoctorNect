import 'package:flutter/foundation.dart';

import 'demo_auth_config.dart';
import '../enums/user_type.dart';
import '../session/ambulance_session.dart';
import '../session/doctor_session.dart';
import '../session/lab_session.dart';
import '../session/medical_store_session.dart';
import '../../features/ambulance/data/ambulance_store.dart';
import '../../features/doctor/models/doctor_models.dart';
import '../../features/doctor/profile/data/doctor_profile_store.dart';
import '../../features/lab/data/lab_registry.dart';
import '../../features/pharmacy/data/medical_store_registry.dart';

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
      'submitted_for_verification' ||
      'pending_review' =>
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
  bool get isRejected => this == VerificationStage.rejected;
  bool get isIncomplete =>
      this == VerificationStage.registered ||
      this == VerificationStage.profileIncomplete;

  /// Non-blocking toast message shown when tapping a locked navigation item or dashboard action.
  String get lockedToastMessage =>
      this == VerificationStage.submittedForVerification
          ? 'Your profile is under verification'
          : 'Complete your profile to unlock this';

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
            description:
                'State or National Medical Council registration number',
          ),
          VerificationRequirementItem(
            key: 'stateCouncil',
            label: 'Registration Authority',
            description: 'Issuing State / National Medical Council',
          ),
          VerificationRequirementItem(
            key: 'registrationCertificate',
            label: 'Registration Certificate',
            description:
                'Official council registration document or certificate',
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

  static bool isFieldFilled(Map<String, dynamic>? data, String key) {
    if (data == null) return false;
    final value = data[key];
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is Map) {
      return value.values.any(
        (v) => v != null && v.toString().trim().isNotEmpty,
      );
    }
    if (value is List) return value.isNotEmpty;
    return true;
  }

  /// Evaluates whether the given profile document data meets all requirements for the role.
  static bool isRequirementsMet(UserType role, Map<String, dynamic>? data) {
    if (data == null) return false;
    final mobile = data['mobile'] as String? ?? data['phone'] as String?;
    if (role == UserType.doctor && DemoAuthConfig.isDemoDoctorPhone(mobile)) {
      return true;
    }
    final items = requirementsForRole(role);
    for (final item in items) {
      if (!isFieldFilled(data, item.key)) return false;
    }
    return true;
  }

  /// Calculates profile completion percentage (0..100) for the given role.
  static int completionPercentage(UserType role, Map<String, dynamic>? data) {
    final items = requirementsForRole(role);
    if (items.isEmpty) return 100;
    if (data == null) return 0;
    final mobile = data['mobile'] as String? ?? data['phone'] as String?;
    if (role == UserType.doctor && DemoAuthConfig.isDemoDoctorPhone(mobile)) {
      return 100;
    }
    var met = 0;
    for (final item in items) {
      if (isFieldFilled(data, item.key)) {
        met++;
      }
    }
    return ((met * 100) / items.length).round().clamp(0, 100);
  }
}

/// Reactive state controller that tracks post-role-selection verification lifecycle
/// (`registered -> profile_incomplete -> submitted_for_verification -> verified`,
/// with reject/resubmit support) across Doctor, Pharmacy, Diagnostic Lab, and Ambulance.
class RoleVerificationController extends ChangeNotifier {
  RoleVerificationController._() {
    DoctorProfileStore.instance.addListener(_onStoreChanged);
    MedicalStoreRegistry.instance.addListener(_onStoreChanged);
    LabRegistry.instance.addListener(_onStoreChanged);
    AmbulanceStore.instance.addListener(_onStoreChanged);
  }

  static final RoleVerificationController instance =
      RoleVerificationController._();

  final Map<UserType, VerificationStage> _stageOverrides = {};
  final Map<UserType, String?> _rejectionReasons = {};
  final Map<UserType, Map<String, dynamic>> _extraRoleData = {};

  void _onStoreChanged() {
    notifyListeners();
  }

  void reset() {
    _stageOverrides.clear();
    _rejectionReasons.clear();
    _extraRoleData.clear();
    notifyListeners();
  }

  VerificationStage stageFor(UserType role) {
    if (role == UserType.patient || role == UserType.superAdmin) {
      return VerificationStage.verified;
    }
    if (role == UserType.doctor) {
      final docId = DoctorSession.loggedInDoctorId;
      final mobile = DoctorProfileStore.instance.profile.mobile;
      if (DemoAuthConfig.isDemoDoctorPhone(docId) ||
          docId.contains(DemoAuthConfig.demoDoctorPhone) ||
          DemoAuthConfig.isDemoDoctorPhone(mobile)) {
        return VerificationStage.verified;
      }
    }
    final override = _stageOverrides[role];
    if (override != null) return override;

    return switch (role) {
      UserType.doctor =>
        DoctorProfileStore.instance.profile.verificationStatus ==
                VerificationStatus.verified
            ? VerificationStage.verified
            : VerificationStage.profileIncomplete,
      UserType.medicalStore => () {
          final id = MedicalStoreSession.loggedInStoreId;
          final store = id.isNotEmpty
              ? MedicalStoreRegistry.findById(id)
              : (MedicalStoreRegistry.all.isNotEmpty
                  ? MedicalStoreRegistry.all.first
                  : null);
          return (store?.verified ?? false)
              ? VerificationStage.verified
              : VerificationStage.profileIncomplete;
        }(),
      UserType.lab => () {
          final id = LabSession.loggedInLabId;
          final lab = id.isNotEmpty
              ? LabRegistry.findById(id)
              : (LabRegistry.all.isNotEmpty ? LabRegistry.all.first : null);
          return (lab?.verified ?? false)
              ? VerificationStage.verified
              : VerificationStage.profileIncomplete;
        }(),
      UserType.ambulance => () {
          final id = AmbulanceSession.loggedInAmbulanceId;
          final amb = id.isNotEmpty
              ? AmbulanceStore.instance.findAmbulance(id)
              : (AmbulanceStore.instance.registeredAmbulances.isNotEmpty
                  ? AmbulanceStore.instance.registeredAmbulances.first
                  : null);
          return (amb?.verified ?? false)
              ? VerificationStage.verified
              : VerificationStage.profileIncomplete;
        }(),
      _ => VerificationStage.verified,
    };
  }

  bool isVerified(UserType role) => stageFor(role).isVerified;

  String? rejectionReasonFor(UserType role) => _rejectionReasons[role];

  bool isRejectedOrBouncedBack(
    UserType role, {
    VerificationStage? effectiveStage,
    String? effectiveReason,
  }) {
    final st = effectiveStage ?? stageFor(role);
    final r = effectiveReason ?? rejectionReasonFor(role);
    return st == VerificationStage.rejected ||
        st == VerificationStage.revisionRequested ||
        (st.isIncomplete && r != null && r.trim().isNotEmpty);
  }

  void setRoleState(
    UserType role, {
    required VerificationStage stage,
    String? rejectionReason,
  }) {
    _stageOverrides[role] = stage;
    if (rejectionReason != null) {
      _rejectionReasons[role] =
          rejectionReason.trim().isEmpty ? null : rejectionReason.trim();
    } else if (stage == VerificationStage.verified ||
        stage == VerificationStage.submittedForVerification) {
      _rejectionReasons.remove(role);
    }
    _syncStoreVerificationFlag(role, stage.isVerified);
    notifyListeners();
  }

  void _syncStoreVerificationFlag(UserType role, bool verified) {
    switch (role) {
      case UserType.doctor:
        DoctorProfileStore.instance.profile.verificationStatus =
            verified ? VerificationStatus.verified : VerificationStatus.pending;
      case UserType.medicalStore:
        final id = MedicalStoreSession.loggedInStoreId;
        final store = id.isNotEmpty ? MedicalStoreRegistry.findById(id) : null;
        if (store != null && store.verified != verified) {
          MedicalStoreRegistry.register(
            id: store.id,
            storeName: store.storeName,
            ownerName: store.ownerName,
            address: store.address,
            drugLicenseNumber: store.drugLicenseNumber,
            phone: store.phone,
            email: store.email,
            gstNumber: store.gstNumber,
            verified: verified,
          );
        }
      case UserType.lab:
        final id = LabSession.loggedInLabId;
        final lab = id.isNotEmpty ? LabRegistry.findById(id) : null;
        if (lab != null && lab.verified != verified) {
          LabRegistry.register(
            id: lab.id,
            labName: lab.labName,
            address: lab.address,
            licenseNumber: lab.licenseNumber,
            phone: lab.phone,
            email: lab.email,
            gstNumber: lab.gstNumber,
            verified: verified,
          );
        }
      case UserType.ambulance:
        final id = AmbulanceSession.loggedInAmbulanceId;
        final amb =
            id.isNotEmpty ? AmbulanceStore.instance.findAmbulance(id) : null;
        if (amb != null && amb.verified != verified) {
          AmbulanceStore.instance.updateRegisteredAmbulance(
            amb.copyWith(verified: verified),
          );
        }
      default:
        break;
    }
  }

  void setExtraField(UserType role, String key, dynamic value) {
    final map = _extraRoleData.putIfAbsent(role, () => <String, dynamic>{});
    map[key] = value;
    if (role == UserType.doctor && value is String) {
      if (key == 'registrationCertificate') {
        DoctorProfileStore.instance.profile.registrationCertificate = value;
      } else if (key == 'idProof') {
        DoctorProfileStore.instance.profile.idProof = value;
      }
    }
    notifyListeners();
  }

  Map<String, dynamic> profileDataFor(
    UserType role, {
    Map<String, dynamic>? firestoreData,
  }) {
    final result = <String, dynamic>{};
    if (firestoreData != null) {
      result.addAll(firestoreData);
    }
    final extra = _extraRoleData[role];
    if (extra != null) {
      extra.forEach((k, v) {
        if (v != null && v.toString().trim().isNotEmpty) {
          result[k] = v;
        }
      });
    }

    switch (role) {
      case UserType.doctor:
        final p = DoctorProfileStore.instance.profile;
        if (p.qualification.trim().isNotEmpty) {
          result['qualification'] = p.qualification.trim();
        }
        if (p.councilNumber.trim().isNotEmpty) {
          result['councilNumber'] = p.councilNumber.trim();
        }
        if (p.stateCouncil.trim().isNotEmpty) {
          result['stateCouncil'] = p.stateCouncil.trim();
        }
        if (p.registrationCertificate.trim().isNotEmpty) {
          result['registrationCertificate'] = p.registrationCertificate.trim();
        }
        if (p.idProof.trim().isNotEmpty) {
          result['idProof'] = p.idProof.trim();
        }
        if (p.mobile.trim().isNotEmpty) {
          result['mobile'] = p.mobile.trim();
        }
      case UserType.medicalStore:
        final id = MedicalStoreSession.loggedInStoreId;
        final store = id.isNotEmpty
            ? MedicalStoreRegistry.findById(id)
            : (MedicalStoreRegistry.all.isNotEmpty
                ? MedicalStoreRegistry.all.first
                : null);
        if (store != null) {
          if (store.storeName.trim().isNotEmpty) {
            result['storeName'] = store.storeName.trim();
          }
          if (store.drugLicenseNumber.trim().isNotEmpty) {
            result['drugLicenseNumber'] = store.drugLicenseNumber.trim();
          }
          if (store.ownerName.trim().isNotEmpty) {
            result['ownerName'] = store.ownerName.trim();
          }
          final addr = store.address.trim().isNotEmpty
              ? store.address.trim()
              : [
                  store.addressLine1,
                  store.city,
                  store.state,
                  store.pincode,
                ].where((s) => s.trim().isNotEmpty).join(', ');
          if (addr.isNotEmpty) {
            result['address'] = addr;
          }
        }
      case UserType.lab:
        final id = LabSession.loggedInLabId;
        final lab = id.isNotEmpty
            ? LabRegistry.findById(id)
            : (LabRegistry.all.isNotEmpty ? LabRegistry.all.first : null);
        if (lab != null) {
          if (lab.labName.trim().isNotEmpty) {
            result['labName'] = lab.labName.trim();
          }
          if (lab.licenseNumber.trim().isNotEmpty) {
            result['licenseNumber'] = lab.licenseNumber.trim();
          }
          final addr = lab.address.trim().isNotEmpty
              ? lab.address.trim()
              : [
                  lab.addressLine1,
                  lab.city,
                  lab.state,
                  lab.pincode,
                ].where((s) => s.trim().isNotEmpty).join(', ');
          if (addr.isNotEmpty) {
            result['address'] = addr;
          }
        }
      case UserType.ambulance:
        final id = AmbulanceSession.loggedInAmbulanceId;
        final amb = id.isNotEmpty
            ? AmbulanceStore.instance.findAmbulance(id)
            : (AmbulanceStore.instance.registeredAmbulances.isNotEmpty
                ? AmbulanceStore.instance.registeredAmbulances.first
                : null);
        if (amb != null) {
          if (amb.serviceName.trim().isNotEmpty) {
            result['serviceName'] = amb.serviceName.trim();
          }
          if (amb.vehicleNumber.trim().isNotEmpty) {
            result['vehicleNumber'] = amb.vehicleNumber.trim();
          }
          if (amb.driverName.trim().isNotEmpty &&
              amb.driverName.trim() != 'Driver') {
            result['driverName'] = amb.driverName.trim();
          } else if (amb.driverName.trim().isNotEmpty &&
              !result.containsKey('driverName')) {
            result['driverName'] = amb.driverName.trim();
          }
          if (amb.licenseNumber.trim().isNotEmpty) {
            result['licenseNumber'] = amb.licenseNumber.trim();
          }
        }
      default:
        break;
    }

    return result;
  }

  int completionPercentageFor(
    UserType role, {
    Map<String, dynamic>? firestoreData,
  }) {
    final data = profileDataFor(role, firestoreData: firestoreData);
    return VerificationRequirementsConfig.completionPercentage(role, data);
  }

  bool canSubmitForVerification(
    UserType role, {
    Map<String, dynamic>? firestoreData,
  }) {
    final data = profileDataFor(role, firestoreData: firestoreData);
    return VerificationRequirementsConfig.isRequirementsMet(role, data);
  }

  List<VerificationRequirementItem> missingRequirementsFor(
    UserType role, {
    Map<String, dynamic>? firestoreData,
  }) {
    final data = profileDataFor(role, firestoreData: firestoreData);
    final items = VerificationRequirementsConfig.requirementsForRole(role);
    return [
      for (final item in items)
        if (!VerificationRequirementsConfig.isFieldFilled(data, item.key)) item,
    ];
  }

  void markSubmittedForVerification(UserType role) {
    setRoleState(role, stage: VerificationStage.submittedForVerification);
  }

  void markVerified(UserType role) {
    setRoleState(role, stage: VerificationStage.verified);
  }

  void markRejected(
    UserType role,
    String reason, {
    VerificationStage stage = VerificationStage.profileIncomplete,
  }) {
    setRoleState(role, stage: stage, rejectionReason: reason);
  }
}
