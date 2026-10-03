import '../enums/user_type.dart';

/// Validation, fake name detection, and greeting formatting for user names.
abstract final class NameValidator {
  static const Set<String> _fakeNames = {
    'doctor',
    'patient',
    'medical',
    'medical store',
    'medicalstore',
    'pharmacy',
    'lab',
    'diagnostic lab',
    'ambulance',
    'ambulance service',
    'super admin',
    'superadmin',
    'user',
    'admin',
  };

  /// Returns null if valid, or a user-facing validation error message.
  static String? validate(String? value) {
    if (value == null) {
      return 'Full name is required.';
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'Full name is required.';
    }
    if (trimmed.length < 2) {
      return 'Full name must be at least 2 characters.';
    }
    if (isFakeName(trimmed)) {
      return 'Please enter your real full name.';
    }
    return null;
  }

  /// True if [name] is valid, trimmed, has >= 2 characters, and is not a fake name.
  static bool isValid(String? name) => validate(name) == null;

  /// Alias for [isValid] to check if a user has a real, valid name.
  static bool isRealName(String? name) => validate(name) == null;

  /// Detects whether [name] is a generic role label or repeated placeholder.
  static bool isFakeName(String? name) {
    if (name == null) return true;
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length < 2) return true;

    final lower = trimmed.toLowerCase();
    if (_fakeNames.contains(lower)) return true;

    // Detect prefixed "Dr. Doctor" or "Dr Doctor"
    if (lower == 'dr. doctor' ||
        lower == 'dr doctor' ||
        lower == 'dr. patient' ||
        lower == 'hi doctor' ||
        lower == 'hi patient') {
      return true;
    }

    // Detect repeated words like "Doctor Doctor", "Patient Patient", "Lab Lab"
    final words = lower.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length >= 2 && words.every((w) => _fakeNames.contains(w))) {
      return true;
    }

    return false;
  }

  /// Formats a proper greeting for the given role:
  /// - Doctors: "Hi, Dr. Rahul Sharma" (or "Hi, Dr. Sharma" if already prefixed)
  /// - Other roles: "Hi, Rahul Sharma"
  /// Returns empty string if the name is invalid or a fake fallback.
  static String formatGreeting(String name, {required UserType role}) {
    final trimmed = name.trim();
    if (isFakeName(trimmed)) return '';

    if (role == UserType.doctor) {
      final lower = trimmed.toLowerCase();
      if (lower.startsWith('dr.') || lower.startsWith('dr ')) {
        return 'Hi, $trimmed';
      }
      return 'Hi, Dr. $trimmed';
    }

    return 'Hi, $trimmed';
  }

  /// Cleans the display name for UI presentation, stripping any fallback role words.
  static String cleanDisplayName(String? name) {
    if (name == null) return '';
    final trimmed = name.trim();
    if (isFakeName(trimmed)) return '';
    return trimmed;
  }
}
