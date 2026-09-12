import '../constants/country_phone_codes.dart';
import 'server_validation_service.dart';

/// Executes validation rules downloaded from the server with comprehensive offline defaults.
abstract final class ValidationEngine {
  static final Map<String, Map<String, dynamic>> _defaultRules = {
    'required': {'kind': 'required'},
    'gender': {'kind': 'dropdown', 'requiredField': 'Gender'},
    'country': {'kind': 'dropdown', 'requiredField': 'Country'},
    'state': {'kind': 'dropdown', 'requiredField': 'State'},
    'city': {'kind': 'dropdown', 'requiredField': 'City'},
    'languages': {'kind': 'multiSelect', 'requiredField': 'Languages spoken'},
    'addressLine1': {'kind': 'required', 'requiredField': 'Address Line 1'},
    'address1': {'kind': 'required', 'requiredField': 'Address Line 1'},
    'addressLine2': {'kind': 'optionalPattern'},
    'dob': {'kind': 'required', 'requiredField': 'Date of birth'},
    'specialization': {'kind': 'required', 'requiredField': 'Specialization'},
    'qualification': {'kind': 'required', 'requiredField': 'Qualification'},
    'experience': {'kind': 'required', 'requiredField': 'Experience'},
    'councilNumber': {'kind': 'required', 'requiredField': 'Medical Council Registration Number'},
    'registrationNumber': {'kind': 'required', 'requiredField': 'Registration Number'},
    'drugLicense': {'kind': 'required', 'requiredField': 'Drug License Number'},
    'gstNumber': {'kind': 'required', 'requiredField': 'GST Number'},
    'labName': {'kind': 'required', 'requiredField': 'Lab Name'},
    'storeName': {'kind': 'required', 'requiredField': 'Store Name'},
    'vehicleNumber': {'kind': 'vehicleNumber', 'requiredField': 'Vehicle Number'},
    'drivingLicense': {'kind': 'required', 'requiredField': 'Driving License Number'},
    'dropdown': {'kind': 'dropdown'},
    'file': {'kind': 'file'},
    'multiSelect': {'kind': 'multiSelect'},
    'email': {
      'kind': 'pattern',
      'required': true,
      'requiredField': 'Email',
      'pattern': r'^[\w.\-]+@([\w\-]+\.)+[\w\-]{2,}$',
      'invalidMessage': 'Enter a valid email address',
    },
    'optionalEmail': {
      'kind': 'optionalPattern',
      'pattern': r'^[\w.\-]+@([\w\-]+\.)+[\w\-]{2,}$',
      'invalidMessage': 'Enter a valid email address',
    },
    'phoneLocal': {
      'kind': 'phoneLocal',
      'required': true,
      'requiredField': 'Phone number',
      'defaultDialCode': '+91',
    },
    'password': {
      'kind': 'required',
      'requiredField': 'Password',
    },
    'confirmPassword': {
      'kind': 'confirmPassword',
      'requiredField': 'Confirm password',
    },
    'otp': {
      'kind': 'pattern',
      'required': true,
      'pattern': r'^\d{6}$',
      'invalidMessage': 'OTP must contain only digits',
      'length': 6,
      'lengthMessage': 'Enter the 6-digit OTP',
    },
    'loginUsername': {
      'kind': 'required',
      'requiredField': 'Username',
    },
    'fullName': {
      'kind': 'minLength',
      'requiredField': 'Full name',
      'minLength': 2,
      'invalidMessage': 'Enter a valid full name',
    },
    'pincode': {
      'kind': 'pattern',
      'required': true,
      'requiredField': 'Pincode',
      'pattern': r'^\d{6}$',
      'invalidMessage': 'Enter a valid 6-digit pincode',
    },
  };

  static String? validate(
    String ruleName,
    dynamic value, {
    Map<String, dynamic>? params,
  }) {
    final rules = ServerValidationService.rules;
    final ruleRaw = rules?[ruleName] ?? _defaultRules[ruleName];

    final field = (params?['field'] as String?) ??
        (ruleRaw is Map ? ruleRaw['requiredField'] as String? : null) ??
        'This field';
    final str = value == null ? '' : value.toString().trim();

    // If no specific rule is configured, evaluate cleanly without blocking valid input
    if (ruleRaw == null) {
      if (value is Iterable) {
        return value.isEmpty && (params?['required'] == true)
            ? 'Please select $field'
            : null;
      }
      if (str.isNotEmpty) return null;
      if (params?['required'] == true) return '$field is required';
      return null;
    }

    if (ruleRaw is! Map) return null;
    final rule = Map<String, dynamic>.from(ruleRaw);

    switch (rule['kind'] as String?) {
      case 'required':
        if (value is Iterable) {
          if (value.isEmpty) return 'Please select $field';
          return null;
        }
        if (str.isEmpty) return '$field is required';
        return null;

      case 'pattern':
        if (str.isEmpty) {
          return '$field is required';
        }
        final minLength = rule['minLength'] as int?;
        if (minLength != null && str.length < minLength) {
          return rule['minLengthMessage'] as String? ??
              rule['invalidMessage'] as String? ??
              'Invalid value';
        }
        final length = rule['length'];
        if (length is int && str.length != length) {
          return rule['lengthMessage'] as String? ??
              rule['invalidMessage'] as String? ??
              'Invalid value';
        }
        final pattern = rule['pattern'] as String?;
        if (pattern != null && !RegExp(pattern).hasMatch(str)) {
          return rule['invalidMessage'] as String? ?? 'Invalid value';
        }
        return null;

      case 'optionalPattern':
        if (str.isEmpty) return null;
        final pattern = rule['pattern'] as String?;
        if (pattern != null && !RegExp(pattern).hasMatch(str)) {
          return rule['invalidMessage'] as String? ?? 'Invalid value';
        }
        return null;

      case 'phoneLocal':
        if (str.isEmpty) return '$field is required';
        final dialCode = (params?['dialCode'] as String?) ??
            (rule['defaultDialCode'] as String?) ??
            CountryPhoneCodes.defaultDialCode;
        final digits = str.replaceAll(RegExp(r'\D'), '');
        if (dialCode == CountryPhoneCodes.defaultDialCode) {
          if (_indianMobileDigits(digits) == null) {
            return 'Enter a valid 10-digit mobile number';
          }
          return null;
        }
        if (digits.length < 4 || digits.length > 15) {
          return 'Enter a valid phone number';
        }
        return null;

      case 'confirmPassword':
        if (str.isEmpty) return '$field is required';
        if (str != (params?['password']?.toString() ?? '')) {
          return 'Passwords do not match';
        }
        return null;

      case 'changePassword':
        if (str.isEmpty) return '$field is required';
        final minLen = rule['minLength'] as int? ?? 6;
        if (str.length < minLen) {
          return rule['invalidMessage'] as String? ??
              'Password must be at least 6 characters';
        }
        if (str == (params?['current']?.toString() ?? '')) {
          return rule['sameAsMessage'] as String? ??
              'New password must differ from current';
        }
        return null;

      case 'intRange':
        if (str.isEmpty) return '$field is required';
        if (ruleName == 'age' && !RegExp(r'^\d{1,3}$').hasMatch(str)) {
          return rule['invalidMessage'] as String? ?? 'Enter a valid age';
        }
        final n = int.tryParse(str);
        final min = (params?['min'] as int?) ?? (rule['min'] as int?) ?? 0;
        final max = (params?['max'] as int?) ?? (rule['max'] as int?) ?? 999;
        if (n == null || n < min || n > max) {
          final template = rule['rangeMessage'] as String? ??
              rule['invalidMessage'] as String? ??
              'Invalid value';
          return template
              .replaceAll('{min}', '$min')
              .replaceAll('{max}', '$max');
        }
        return null;

      case 'minLength':
        if (str.isEmpty) return '$field is required';
        final minLength = rule['minLength'] as int? ?? 1;
        if (str.length < minLength) {
          return rule['invalidMessage'] as String? ?? 'Invalid value';
        }
        final maxLength = rule['maxLength'] as int?;
        if (maxLength != null && str.length > maxLength) {
          return rule['maxLengthMessage'] as String? ??
              rule['invalidMessage'] as String? ??
              'Invalid value';
        }
        return null;

      case 'vehicleNumber':
        if (str.isEmpty) return '$field is required';
        final normalized = str.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();
        final patternsRaw = rule['patterns'] as List?;
        final patterns = patternsRaw?.map((p) => '$p').toList() ??
            const [
              r'^[A-Z]{2}[0-9]{1,2}[A-Z]{1,3}[0-9]{1,4}$',
              r'^[0-9]{2}BH[0-9]{4}[A-Z]{2}$',
            ];
        final matched = patterns.any((p) => RegExp(p).hasMatch(normalized));
        if (!matched) {
          return rule['invalidMessage'] as String? ??
              'Enter a valid vehicle number (e.g. MH-12-AB-4521)';
        }
        return null;

      case 'dropdown':
        if (value == null || value.toString().trim().isEmpty) {
          return 'Please select $field';
        }
        return null;

      case 'file':
        if (value == null || value.toString().trim().isEmpty) {
          return 'Please upload $field';
        }
        return null;

      case 'multiSelect':
        final selected = params?['selected'] ?? value;
        final count = selected is Iterable ? selected.length : (selected != null && selected.toString().isNotEmpty ? 1 : 0);
        if (count == 0) return 'Please select at least one $field';
        return null;

      case 'optionalNumeric':
        if (str.isEmpty) return null;
        final parsed = double.tryParse(str);
        final label = rule['label'] as String? ?? field;
        if (parsed == null) return 'Enter a valid $label';
        final min = (rule['min'] as num?)?.toDouble();
        final max = (rule['max'] as num?)?.toDouble();
        if (min != null && parsed < min) return '$label is too low';
        if (max != null && parsed > max) return '$label is too high';
        return null;

      case 'bloodPressure':
        if (str.isEmpty) return null;
        final formatPattern =
            rule['formatPattern'] as String? ?? r'^(\d{2,3})/(\d{2,3})$';
        final match = RegExp(formatPattern).firstMatch(str);
        if (match == null) {
          return rule['formatMessage'] as String? ??
              'Enter BP as systolic/diastolic (e.g. 120/80)';
        }
        final sys = int.tryParse(match.group(1)!);
        final dia = int.tryParse(match.group(2)!);
        if (sys == null || dia == null) {
          return rule['invalidMessage'] as String? ??
              'Enter a valid blood pressure';
        }
        if (sys <= dia) {
          return rule['orderMessage'] as String? ??
              'Systolic BP must be higher than diastolic BP';
        }
        final sysMin = (rule['sysMin'] as num?)?.toInt() ?? 50;
        final sysMax = (rule['sysMax'] as num?)?.toInt() ?? 250;
        final diaMin = (rule['diaMin'] as num?)?.toInt() ?? 30;
        final diaMax = (rule['diaMax'] as num?)?.toInt() ?? 150;
        if (sys < sysMin ||
            sys > sysMax ||
            dia < diaMin ||
            dia > diaMax) {
          return rule['plausibleMessage'] as String? ??
              'Enter a plausible blood pressure';
        }
        return null;

      default:
        return null;
    }
  }

  static String? _indianMobileDigits(String digits) {
    var normalized = digits.replaceAll(RegExp(r'\D'), '');
    if (normalized.length == 12 && normalized.startsWith('91')) {
      normalized = normalized.substring(2);
    } else if (normalized.length == 11 && normalized.startsWith('0')) {
      normalized = normalized.substring(1);
    }
    if (normalized.length != 10 || !RegExp(r'^[6-9]').hasMatch(normalized)) {
      return null;
    }
    return normalized;
  }
}
