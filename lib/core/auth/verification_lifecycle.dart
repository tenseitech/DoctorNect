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
      'pending_review' => VerificationStage.submittedForVerification,
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
    required this.section,
    this.description = '',
    this.isDocument = false,
  });

  final String key;
  final String label;
  final String section;
  final String description;
  final bool isDocument;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VerificationRequirementItem &&
          runtimeType == other.runtimeType &&
          key == other.key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => key;
}

/// Configurable verification requirements per role.
/// Single source of truth for profile completeness across professional/service roles.
abstract final class VerificationRequirementsConfig {
  static List<VerificationRequirementItem> requirementsForRole(UserType role) {
    return switch (role) {
      UserType.doctor => const [
        VerificationRequirementItem(
          key: 'name',
          label: 'Full Name',
          section: 'Personal Information',
          description: "Doctor's full legal name",
        ),
        VerificationRequirementItem(
          key: 'mobile',
          label: 'Mobile Number',
          section: 'Personal Information',
          description: 'Registered mobile contact number',
        ),
        VerificationRequirementItem(
          key: 'qualification',
          label: 'Medical Degree / Qualification',
          section: 'Professional Details',
          description: 'Recognized medical degree (e.g., MBBS, MD, MS)',
        ),
        VerificationRequirementItem(
          key: 'specialization',
          label: 'Specialization',
          section: 'Professional Details',
          description: 'Primary medical area of expertise',
        ),
        VerificationRequirementItem(
          key: 'councilNumber',
          label: 'Medical Registration Number',
          section: 'Professional Details',
          description: 'State or National Medical Council registration number',
        ),
        VerificationRequirementItem(
          key: 'stateCouncil',
          label: 'Registration Authority',
          section: 'Professional Details',
          description: 'Issuing State / National Medical Council',
        ),
        VerificationRequirementItem(
          key: 'registrationCertificate',
          label: 'Registration Certificate',
          section: 'Professional Details',
          description: 'Official council registration document or certificate',
          isDocument: true,
        ),
        VerificationRequirementItem(
          key: 'idProof',
          label: 'Identity Proof',
          section: 'Professional Details',
          description: 'Government-issued photo identification',
          isDocument: true,
        ),
        VerificationRequirementItem(
          key: 'country',
          label: 'Clinic Country',
          section: 'Clinic Information',
          description: 'Country where the clinic is located',
        ),
        VerificationRequirementItem(
          key: 'state',
          label: 'Clinic State',
          section: 'Clinic Information',
          description: 'State or province of the clinic',
        ),
        VerificationRequirementItem(
          key: 'city',
          label: 'Clinic City',
          section: 'Clinic Information',
          description: 'City or town of the clinic',
        ),
        VerificationRequirementItem(
          key: 'addressLine1',
          label: 'Clinic Street Address',
          section: 'Clinic Information',
          description: 'Street address or building of the clinic',
        ),
        VerificationRequirementItem(
          key: 'pinCode',
          label: 'Clinic PIN Code',
          section: 'Clinic Information',
          description: 'Postal / PIN code of the clinic',
        ),
      ],
      UserType.medicalStore => const [
        VerificationRequirementItem(
          key: 'storeName',
          label: 'Pharmacy / Store Name',
          section: 'Store Details',
          description: 'Registered business name of the medical store',
        ),
        VerificationRequirementItem(
          key: 'ownerName',
          label: 'Owner / Pharmacist Name',
          section: 'Store Details',
          description: 'Name of the licensed pharmacist or owner',
        ),
        VerificationRequirementItem(
          key: 'phone',
          label: 'Phone Number',
          section: 'Store Details',
          description: 'Contact phone number for the store',
        ),
        VerificationRequirementItem(
          key: 'drugLicenseNumber',
          label: 'Drug License Number',
          section: 'Store Details',
          description: 'Valid Form 20/21 drug retail license number',
        ),
        VerificationRequirementItem(
          key: 'country',
          label: 'Country',
          section: 'Address',
          description: 'Country of the store location',
        ),
        VerificationRequirementItem(
          key: 'state',
          label: 'State',
          section: 'Address',
          description: 'State or province of the store',
        ),
        VerificationRequirementItem(
          key: 'city',
          label: 'City',
          section: 'Address',
          description: 'City of the store',
        ),
        VerificationRequirementItem(
          key: 'addressLine1',
          label: 'Address Line 1',
          section: 'Address',
          description: 'Street address or shop number',
        ),
        VerificationRequirementItem(
          key: 'pincode',
          label: 'PIN Code',
          section: 'Address',
          description: 'Postal / PIN code of the store',
        ),
      ],
      UserType.lab => const [
        VerificationRequirementItem(
          key: 'labName',
          label: 'Diagnostic Lab Name',
          section: 'Lab Details',
          description: 'Registered diagnostic centre or laboratory name',
        ),
        VerificationRequirementItem(
          key: 'phone',
          label: 'Phone Number',
          section: 'Lab Details',
          description: 'Contact phone number for the diagnostic centre',
        ),
        VerificationRequirementItem(
          key: 'licenseNumber',
          label: 'Clinical Establishment License',
          section: 'Lab Details',
          description: 'Valid diagnostic/pathology registration number',
        ),
        VerificationRequirementItem(
          key: 'country',
          label: 'Country',
          section: 'Address',
          description: 'Country of the laboratory facility',
        ),
        VerificationRequirementItem(
          key: 'state',
          label: 'State',
          section: 'Address',
          description: 'State or province of the laboratory',
        ),
        VerificationRequirementItem(
          key: 'city',
          label: 'City',
          section: 'Address',
          description: 'City of the laboratory facility',
        ),
        VerificationRequirementItem(
          key: 'addressLine1',
          label: 'Address Line 1',
          section: 'Address',
          description: 'Street address of the laboratory',
        ),
        VerificationRequirementItem(
          key: 'pincode',
          label: 'PIN Code',
          section: 'Address',
          description: 'Postal / PIN code of the laboratory facility',
        ),
      ],
      UserType.ambulance => const [
        VerificationRequirementItem(
          key: 'serviceName',
          label: 'Ambulance Service Name',
          section: 'Service Details',
          description: 'Fleet or emergency transport service name',
        ),
        VerificationRequirementItem(
          key: 'driverName',
          label: 'Driver / Operator Name',
          section: 'Driver Details',
          description: 'Name of the designated ambulance driver',
        ),
        VerificationRequirementItem(
          key: 'phone',
          label: 'Phone Number',
          section: 'Driver Details',
          description: 'Contact phone number for emergency dispatch',
        ),
        VerificationRequirementItem(
          key: 'vehicleNumber',
          label: 'Vehicle Registration Number',
          section: 'Service Details',
          description: 'Commercial motor vehicle registration number',
        ),
        VerificationRequirementItem(
          key: 'licenseNumber',
          label: 'Driver License Number',
          section: 'Driver Details',
          description: 'Commercial driving license number',
        ),
        VerificationRequirementItem(
          key: 'city',
          label: 'Operating City',
          section: 'Service Coverage',
          description: 'Primary operational city',
        ),
        VerificationRequirementItem(
          key: 'serviceAreas',
          label: 'Service Areas',
          section: 'Service Coverage',
          description: 'Specific coverage zones or neighborhoods (minimum 1)',
        ),
        VerificationRequirementItem(
          key: 'country',
          label: 'Country',
          section: 'Base Address',
          description: 'Country of vehicle base or dispatch station',
        ),
        VerificationRequirementItem(
          key: 'state',
          label: 'State',
          section: 'Base Address',
          description: 'State or province of vehicle base',
        ),
        VerificationRequirementItem(
          key: 'addressLine1',
          label: 'Base Address',
          section: 'Base Address',
          description: 'Physical garage or station address',
        ),
        VerificationRequirementItem(
          key: 'pincode',
          label: 'PIN Code',
          section: 'Base Address',
          description: 'Postal / PIN code of the station',
        ),
      ],
      _ => const [],
    };
  }

  static bool isFieldFilled(Map<String, dynamic>? data, String key) {
    if (data == null) return false;
    dynamic value = data[key];

    // Common aliases & fallbacks
    if (value == null) {
      if (key == 'name') {
        value = data['fullName'] ?? data['displayName'];
      } else if (key == 'mobile') {
        value = data['phone'];
      } else if (key == 'phone') {
        value = data['mobile'];
      } else if (key == 'labName') {
        value = data['name'];
      } else if (key == 'pinCode') {
        value = data['pincode'];
      } else if (key == 'pincode') {
        value = data['pinCode'];
      }
    }

    // Look inside nested 'address' or 'clinicAddress' map if needed
    if (value == null) {
      final address = data['address'];
      if (address is Map) {
        value = address[key];
        if (value == null) {
          if (key == 'pinCode') {
            value = address['pincode'];
          } else if (key == 'pincode') {
            value = address['pinCode'];
          }
        }
      }
    }
    if (value == null) {
      final clinicAddress = data['clinicAddress'];
      if (clinicAddress is Map) {
        value = clinicAddress[key];
        if (value == null) {
          if (key == 'pinCode') {
            value = clinicAddress['pincode'];
          } else if (key == 'pincode') {
            value = clinicAddress['pinCode'];
          }
        }
      }
    }

    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    if (value is List) return value.isNotEmpty;
    if (value is Map) {
      return value.values.any(
        (v) => v != null && v.toString().trim().isNotEmpty,
      );
    }
    return true;
  }

  /// Evaluates whether the given profile data meets all requirements for the role.
  static bool isComplete(UserType role, Map<String, dynamic>? data) {
    final items = requirementsForRole(role);
    if (items.isEmpty) return true;
    if (data == null) return false;

    final mobile = data['mobile'] as String? ?? data['phone'] as String?;
    final docId = data['doctorId'] as String? ?? data['id'] as String?;
    if (role == UserType.doctor &&
        (DemoAuthConfig.isDemoDoctorPhone(mobile) ||
            DemoAuthConfig.isDemoDoctorPhone(docId) ||
            (docId != null && docId.contains(DemoAuthConfig.demoDoctorPhone)))) {
      return true;
    }

    for (final item in items) {
      if (!isFieldFilled(data, item.key)) return false;
    }
    return true;
  }

  /// Alias for backward compatibility with existing callers.
  static bool isRequirementsMet(UserType role, Map<String, dynamic>? data) =>
      isComplete(role, data);

  /// Calculates profile completion percentage (0..100) for the given role.
  static int completionPercentage(UserType role, Map<String, dynamic>? data) {
    final items = requirementsForRole(role);
    if (items.isEmpty) return 100;
    if (data == null) return 0;

    final mobile = data['mobile'] as String? ?? data['phone'] as String?;
    final docId = data['doctorId'] as String? ?? data['id'] as String?;
    if (role == UserType.doctor &&
        (DemoAuthConfig.isDemoDoctorPhone(mobile) ||
            DemoAuthConfig.isDemoDoctorPhone(docId) ||
            (docId != null && docId.contains(DemoAuthConfig.demoDoctorPhone)))) {
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

  /// Returns the list of requirement items that are missing or incomplete.
  static List<VerificationRequirementItem> missingFields(
    UserType role,
    Map<String, dynamic>? data,
  ) {
    if (data != null) {
      final mobile = data['mobile'] as String? ?? data['phone'] as String?;
      final docId = data['doctorId'] as String? ?? data['id'] as String?;
      if (role == UserType.doctor &&
          (DemoAuthConfig.isDemoDoctorPhone(mobile) ||
              DemoAuthConfig.isDemoDoctorPhone(docId) ||
              (docId != null && docId.contains(DemoAuthConfig.demoDoctorPhone)))) {
        return const [];
      }
    }
    final items = requirementsForRole(role);
    if (data == null) return items;
    return [
      for (final item in items)
        if (!isFieldFilled(data, item.key)) item,
    ];
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
      _rejectionReasons[role] = rejectionReason.trim().isEmpty
          ? null
          : rejectionReason.trim();
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
        DoctorProfileStore.instance.profile.verificationStatus = verified
            ? VerificationStatus.verified
            : VerificationStatus.pending;
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
        final amb = id.isNotEmpty
            ? AmbulanceStore.instance.findAmbulance(id)
            : null;
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
        if (p.fullName.trim().isNotEmpty) {
          result['name'] = p.fullName.trim();
        }
        if (p.qualification.trim().isNotEmpty) {
          result['qualification'] = p.qualification.trim();
        }
        if (p.specialization.trim().isNotEmpty) {
          result['specialization'] = p.specialization.trim();
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
        if (p.country.trim().isNotEmpty) {
          result['country'] = p.country.trim();
        }
        if (p.state.trim().isNotEmpty) {
          result['state'] = p.state.trim();
        }
        if (p.city.trim().isNotEmpty) {
          result['city'] = p.city.trim();
        }
        if (p.addressLine1.trim().isNotEmpty) {
          result['addressLine1'] = p.addressLine1.trim();
        }
        if (p.pincode.trim().isNotEmpty) {
          result['pinCode'] = p.pincode.trim();
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
          if (store.phone.trim().isNotEmpty) {
            result['phone'] = store.phone.trim();
          }
          if (store.country.trim().isNotEmpty) {
            result['country'] = store.country.trim();
          }
          if (store.state.trim().isNotEmpty) {
            result['state'] = store.state.trim();
          }
          if (store.city.trim().isNotEmpty) {
            result['city'] = store.city.trim();
          }
          if (store.addressLine1.trim().isNotEmpty) {
            result['addressLine1'] = store.addressLine1.trim();
          }
          if (store.pincode.trim().isNotEmpty) {
            result['pincode'] = store.pincode.trim();
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
          if (lab.phone.trim().isNotEmpty) {
            result['phone'] = lab.phone.trim();
          }
          if (lab.country.trim().isNotEmpty) {
            result['country'] = lab.country.trim();
          }
          if (lab.state.trim().isNotEmpty) {
            result['state'] = lab.state.trim();
          }
          if (lab.city.trim().isNotEmpty) {
            result['city'] = lab.city.trim();
          }
          if (lab.addressLine1.trim().isNotEmpty) {
            result['addressLine1'] = lab.addressLine1.trim();
          }
          if (lab.pincode.trim().isNotEmpty) {
            result['pincode'] = lab.pincode.trim();
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
          if (amb.phone.trim().isNotEmpty) {
            result['phone'] = amb.phone.trim();
          }
          if (amb.city.trim().isNotEmpty) {
            result['city'] = amb.city.trim();
          }
          if (amb.serviceAreas.isNotEmpty) {
            result['serviceAreas'] = amb.serviceAreas;
          }
          if (amb.country.trim().isNotEmpty) {
            result['country'] = amb.country.trim();
          }
          if (amb.state.trim().isNotEmpty) {
            result['state'] = amb.state.trim();
          }
          if (amb.addressLine1.trim().isNotEmpty) {
            result['addressLine1'] = amb.addressLine1.trim();
          }
          if (amb.pincode.trim().isNotEmpty) {
            result['pincode'] = amb.pincode.trim();
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
    return VerificationRequirementsConfig.isComplete(role, data);
  }

  List<VerificationRequirementItem> missingRequirementsFor(
    UserType role, {
    Map<String, dynamic>? firestoreData,
  }) {
    final data = profileDataFor(role, firestoreData: firestoreData);
    return VerificationRequirementsConfig.missingFields(role, data);
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
