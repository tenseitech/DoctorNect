import '../enums/user_type.dart';
import '../validators/form_validators.dart';

class StoredCredential {
  const StoredCredential({
    required this.id,
    required this.displayName,
    this.mobile,
  });

  final String id;
  final String displayName;
  final String? mobile;
}

/// In-memory email/mobile lookup for the current app session only.
/// Passwords are never stored — Firebase Auth handles credentials.
abstract final class AppCredentialStore {
  static final Map<String, StoredCredential> _doctors = {};
  static final Map<String, StoredCredential> _patients = {};
  static final Map<String, StoredCredential> _stores = {};
  static final Map<String, StoredCredential> _labs = {};

  static void registerDoctor({
    required String email,
    required String id,
    required String name,
    required String mobile,
  }) {
    _doctors[email.trim().toLowerCase()] = StoredCredential(
      id: id,
      displayName: name,
      mobile: mobile,
    );
  }

  static void registerPatient({
    required String email,
    required String id,
    required String name,
    required String mobile,
  }) {
    _patients[email.trim().toLowerCase()] = StoredCredential(
      id: id,
      displayName: name,
      mobile: mobile,
    );
  }

  static void registerStore({
    required String email,
    required String id,
    required String storeName,
    required String mobile,
  }) {
    _stores[email.trim().toLowerCase()] = StoredCredential(
      id: id,
      displayName: storeName,
      mobile: mobile,
    );
  }

  static void registerLab({
    required String email,
    required String id,
    required String labName,
    required String mobile,
  }) {
    _labs[email.trim().toLowerCase()] = StoredCredential(
      id: id,
      displayName: labName,
      mobile: mobile,
    );
  }

  static void registerForRole({
    required UserType role,
    required String email,
    required String id,
    required String displayName,
    String? mobile,
  }) {
    switch (role) {
      case UserType.doctor:
        registerDoctor(
          email: email,
          id: id,
          name: displayName,
          mobile: mobile ?? '',
        );
      case UserType.patient:
        registerPatient(
          email: email,
          id: id,
          name: displayName,
          mobile: mobile ?? '',
        );
      case UserType.medicalStore:
        registerStore(
          email: email,
          id: id,
          storeName: displayName,
          mobile: mobile ?? '',
        );
      case UserType.lab:
        registerLab(
          email: email,
          id: id,
          labName: displayName,
          mobile: mobile ?? '',
        );
      case UserType.ambulance:
      case UserType.superAdmin:
        break;
    }
  }

  static void clearAll() {
    _doctors.clear();
    _patients.clear();
    _stores.clear();
    _labs.clear();
  }

  /// Resolves registered email from mobile (session cache after registration).
  static String? findEmailByMobile(UserType role, String mobile) {
    final digits = FormValidators.mobileDigits(mobile);
    if (digits == null) return null;

    final Iterable<MapEntry<String, StoredCredential>> entries = switch (role) {
      UserType.superAdmin => const Iterable.empty(),
      UserType.doctor => _doctors.entries,
      UserType.patient => _patients.entries,
      UserType.medicalStore => _stores.entries,
      UserType.lab => _labs.entries,
      UserType.ambulance => const Iterable.empty(),
    };

    for (final entry in entries) {
      final stored = entry.value.mobile;
      if (stored == null) continue;
      if (FormValidators.mobileDigits(stored) == digits) {
        return entry.key;
      }
    }
    return null;
  }
}
