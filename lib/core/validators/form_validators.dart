import '../constants/country_phone_codes.dart';
import '../security/input_sanitize.dart';
import '../validation/validation_engine.dart';

class ParsedPhone {
  const ParsedPhone({
    required this.dialCode,
    required this.localNumber,
  });

  final String dialCode;
  final String localNumber;
}

/// Form helpers — validation rules are loaded from the server via [ValidationEngine].
class FormValidators {
  static String? required(String? value, {String field = 'This field'}) =>
      ValidationEngine.validate('required', value, params: {'field': field});

  /// Patient height in feet (1–8). Rejects cm-style values such as 180.
  static String? heightFeet(String? value) {
    final err = required(value, field: 'Feet');
    if (err != null) return err;
    final feet = int.tryParse(value!.trim()) ?? -1;
    if (feet < 1 || feet > 8) return 'Enter 1–8 ft';
    return null;
  }

  /// Patient height remainder in inches (0–11).
  static String? heightInches(String? value) {
    final err = required(value, field: 'Inches');
    if (err != null) return err;
    final inches = int.tryParse(value!.trim()) ?? -1;
    if (inches < 0 || inches > 11) return 'Enter 0–11 in';
    return null;
  }

  static String? fullName(String? value) =>
      ValidationEngine.validate('fullName', value);

  static String? email(String? value) =>
      ValidationEngine.validate('email', value);

  static String? optionalEmail(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return ValidationEngine.validate('optionalEmail', trimmed);
  }

  static String? mobile(String? value) =>
      phoneLocal(value, dialCode: CountryPhoneCodes.defaultDialCode);

  static ParsedPhone parsePhone(
    String? value, {
    String? fallbackDialCode,
  }) {
    final fallback = fallbackDialCode ?? CountryPhoneCodes.defaultDialCode;
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) {
      return ParsedPhone(dialCode: fallback, localNumber: '');
    }

    if (trimmed.startsWith('+')) {
      for (final entry in CountryPhoneCodes.sortedByDialCodeLengthDesc()) {
        if (trimmed.startsWith(entry.dialCode)) {
          final local = trimmed
              .substring(entry.dialCode.length)
              .replaceAll(RegExp(r'\D'), '');
          return ParsedPhone(dialCode: entry.dialCode, localNumber: local);
        }
      }
    }

    var digits = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12 && digits.startsWith('91')) {
      return ParsedPhone(
        dialCode: '+91',
        localNumber: digits.substring(2),
      );
    }
    if (digits.length == 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }

    return ParsedPhone(dialCode: fallback, localNumber: digits);
  }

  static String formatFullPhone(String dialCode, String local) {
    final localDigits = local.replaceAll(RegExp(r'\D'), '');
    return '$dialCode$localDigits';
  }

  static String? phoneLocal(String? value, {required String dialCode}) =>
      ValidationEngine.validate(
        'phoneLocal',
        value,
        params: {'dialCode': dialCode},
      );

  static String? mobileDigits(String value) {
    final parsed = parsePhone(value);
    if (parsed.dialCode == CountryPhoneCodes.defaultDialCode) {
      return _indianMobileDigits(parsed.localNumber);
    }
    if (parsed.localNumber.length >= 4 && parsed.localNumber.length <= 15) {
      return parsed.localNumber;
    }
    return null;
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

  static String? registrationMobileDigits(String value) {
    var digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12 && digits.startsWith('91')) {
      digits = digits.substring(2);
    } else if (digits.length == 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (digits.length != 10 || !RegExp(r'^[6-9]').hasMatch(digits)) {
      return null;
    }
    return digits;
  }

  static String? registrationMobile(String? value,
          {String dialCode = CountryPhoneCodes.defaultDialCode}) =>
      phoneLocal(value, dialCode: dialCode);

  static String? password(String? value) {
    final str = value ?? '';
    if (str.isEmpty) return 'Password is required';

    final missing = <String>[];
    if (str.length < 8) missing.add('8+ characters');
    if (!RegExp(r'[A-Z]').hasMatch(str))
      missing.add('1 uppercase letter (A-Z)');
    if (!RegExp(r'[a-z]').hasMatch(str))
      missing.add('1 lowercase letter (a-z)');
    if (!RegExp(r'[0-9]').hasMatch(str)) missing.add('1 number (0-9)');
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>_\-\+=/\\]').hasMatch(str)) {
      missing.add('1 special character (!@#\$%^&*)');
    }

    if (missing.isNotEmpty) {
      if (missing.length == 1) {
        return 'Password needs ${missing.first}';
      }
      return 'Password needs: ${missing.join(', ')}';
    }
    return null;
  }

  static String? confirmPassword(String? value, String password) =>
      ValidationEngine.validate(
        'confirmPassword',
        value,
        params: {'password': password},
      );

  static String? pincode(String? value, {String? country}) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return 'PIN / postal code is required';
    final isIndia =
        country == null || country.isEmpty || country.toLowerCase() == 'india';
    if (isIndia) {
      if (!RegExp(r'^\d{6}$').hasMatch(trimmed)) {
        return 'Enter a valid 6-digit PIN code';
      }
    } else {
      if (trimmed.length < 3 || trimmed.length > 10) {
        return 'Enter a valid postal code';
      }
    }
    return null;
  }

  static String? age(String? value, {int min = 1, int max = 120}) =>
      ValidationEngine.validate(
        'age',
        value,
        params: {'min': min, 'max': max},
      );

  static String? experience(String? value) =>
      ValidationEngine.validate('experience', value);

  static String? consultationDuration(String? value) =>
      ValidationEngine.validate('consultationDuration', value);

  static String? reminderHours(String? value) =>
      ValidationEngine.validate('reminderHours', value);

  static String? councilNumber(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return 'Council registration number is required';
    if (!RegExp(r'^[A-Z0-9-\/]{4,20}$', caseSensitive: false)
        .hasMatch(trimmed)) {
      return 'Enter a valid council registration number, e.g. MCI-12345 or MH2020123456';
    }
    return null;
  }

  static String? drugLicenseNumber(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return 'Drug license number is required';
    if (!RegExp(
            r'^(?:DL|DLIC|LIC|FORM20|FORM21)?[-\/]?[A-Z]{0,3}[-\/]?\d{4,8}(?:[-\/]\d{2,4})?$',
            caseSensitive: false)
        .hasMatch(trimmed)) {
      return 'Enter a valid drug license number, e.g. DL-12345/2026';
    }
    return null;
  }

  static String? labLicenseNumber(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return 'Lab license number is required';
    if (!RegExp(
            r'^(?:LAB|NABL|REG|LIC)?[-\/]?[A-Z]{0,3}[-\/]?\d{4,8}(?:[-\/]\d{2,4})?$',
            caseSensitive: false)
        .hasMatch(trimmed)) {
      return 'Enter a valid lab license number, e.g. LAB-12345 or NABL/123456';
    }
    return null;
  }

  static String? drivingLicense(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return 'License / permit number is required';
    final normalized =
        trimmed.replaceAll(RegExp(r'[\s\-\/]'), '').toUpperCase();
    if (!RegExp(r'^[A-Z]{2}\d{2}\d{4}\d{7}$').hasMatch(normalized) &&
        !RegExp(r'^(?:PERMIT|AMB|TAXI)[A-Z0-9]{5,16}$').hasMatch(normalized)) {
      return 'Enter a valid driving license or permit number, e.g. MH1220261234567';
    }
    return null;
  }

  /// Driver's driving license number (Indian format).
  static String? ambulanceDrivingLicense(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return 'Driving license number is required';
    final normalized =
        trimmed.replaceAll(RegExp(r'[\s\-\/]'), '').toUpperCase();
    if (!RegExp(r'^[A-Z]{2}\d{2}\d{4}\d{7}$').hasMatch(normalized)) {
      return 'Enter a valid driving license number, e.g. MH1220261234567';
    }
    return null;
  }

  /// Ambulance permit / fitness certificate number.
  static String? ambulancePermitNumber(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) {
      return 'Ambulance permit / fitness certificate number is required';
    }
    if (!RegExp(r'^(?:PERMIT|AMB|FIT|FC|CERT)[A-Z0-9\-\/]{3,20}$',
            caseSensitive: false)
        .hasMatch(trimmed)) {
      return 'Enter a valid permit/fitness certificate number, e.g. AMB-12345/2026';
    }
    return null;
  }

  static String? vehicleInsuranceNumber(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return 'Vehicle insurance number is required';
    if (!RegExp(
            r'^(?:POL|INS|GIC)?[-\/]?[A-Z]{0,4}[-\/]?\d{6,12}(?:[-\/]\d{2,4})?$',
            caseSensitive: false)
        .hasMatch(trimmed)) {
      return 'Enter a valid insurance policy number, e.g. POL-12345678';
    }
    return null;
  }

  static String? insuranceNumber(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return null;
    if (!RegExp(
            r'^(?:POL|INS|GIC)?[-\/]?[A-Z]{0,4}[-\/]?\d{6,12}(?:[-\/]\d{2,4})?$',
            caseSensitive: false)
        .hasMatch(trimmed)) {
      return 'Enter a valid insurance policy number, e.g. POL-12345678';
    }
    return null;
  }

  static String normalizeVehicleNumber(String value) =>
      value.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();

  static String? vehicleNumber(String? value) =>
      ValidationEngine.validate('vehicleNumber', value);

  static String? otp(String? value) => ValidationEngine.validate('otp', value);

  static String? username(String? value) =>
      ValidationEngine.validate('username', value);

  static String? securityPin(String? value) =>
      ValidationEngine.validate('securityPin', value);

  static String? confirmSecurityPin(String? value, String pin) =>
      ValidationEngine.validate(
        'confirmSecurityPin',
        value,
        params: {'password': pin},
      );

  static String? walkInAge(String? value) =>
      ValidationEngine.validate('walkInAge', value);

  static String? patientName(String? value) =>
      ValidationEngine.validate('patientName', value);

  static String? primaryDiagnosis(String? value) =>
      ValidationEngine.validate('primaryDiagnosis', value);

  static String? tagText(String? value, {String field = 'Value'}) =>
      ValidationEngine.validate('tagText', value, params: {'field': field});

  static String? helpMessage(String? value) =>
      ValidationEngine.validate('helpMessage', value);

  /// Free-text fields (reviews, ad copy, locations) — length + script stripping.
  static String? safeText(
    String? value, {
    String field = 'This field',
    int minLength = 1,
    int maxLength = InputSanitize.maxMessageLength,
  }) =>
      InputSanitize.validatePlainText(
        value,
        field: field,
        minLength: minLength,
        maxLength: maxLength,
      );

  static String? reviewText(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    return safeText(
      trimmed,
      field: 'Review',
      minLength: 1,
      maxLength: InputSanitize.maxReviewLength,
    );
  }

  static String? adTitle(String? value) => safeText(
        value,
        field: 'Title',
        minLength: 3,
        maxLength: InputSanitize.maxAdTitleLength,
      );

  static String? adDescription(String? value) => safeText(
        value,
        field: 'Description',
        minLength: 10,
        maxLength: InputSanitize.maxAdDescriptionLength,
      );

  static String? locationText(String? value, {String field = 'Location'}) =>
      safeText(
        value,
        field: field,
        minLength: 3,
        maxLength: InputSanitize.maxLocationLength,
      );

  static String? pdfUpload(String? path, {int? byteLength}) {
    final presence = file(path, field: 'PDF');
    if (presence != null) return presence;
    final name = InputSanitize.fileName(path);
    if (!InputSanitize.isAllowedPdf(name)) {
      return 'Only PDF files are allowed';
    }
    if (byteLength != null) {
      return InputSanitize.validateUploadBytes(
        byteLength: byteLength,
        maxBytes: InputSanitize.maxPdfBytes,
        field: 'PDF',
      );
    }
    return null;
  }

  static String? imageUpload(String? path, {int? byteLength}) {
    final presence = file(path, field: 'Image');
    if (presence != null) return presence;
    final name = InputSanitize.fileName(path);
    if (!InputSanitize.isAllowedImage(name)) {
      return 'Only JPG, PNG, or WebP images are allowed';
    }
    if (byteLength != null) {
      return InputSanitize.validateUploadBytes(
        byteLength: byteLength,
        maxBytes: InputSanitize.maxImageBytes,
        field: 'Image',
      );
    }
    return null;
  }

  static String? maxAppointments(String? value) =>
      ValidationEngine.validate('maxAppointments', value);

  static String? currentPassword(String? value) =>
      ValidationEngine.validate('currentPassword', value);

  static String? newPassword(String? value) =>
      ValidationEngine.validate('newPassword', value);

  static String? changePassword(String? value, String currentPassword) =>
      ValidationEngine.validate(
        'changePassword',
        value,
        params: {'current': currentPassword},
      );

  static String? confirmNewPassword(String? value, String password) =>
      ValidationEngine.validate(
        'confirmNewPassword',
        value,
        params: {'password': password},
      );

  static String? loginUsername(String? value) =>
      ValidationEngine.validate('loginUsername', value);

  static String? loginSecurityPin(String? value) =>
      ValidationEngine.validate('loginSecurityPin', value);

  static String? pincodeIndia(String? value) =>
      ValidationEngine.validate('pincode', value);

  static String? dropdown(String? value, {String field = 'Selection'}) =>
      ValidationEngine.validate('dropdown', value, params: {'field': field});

  static String? file(String? path, {String field = 'File'}) =>
      ValidationEngine.validate('file', path, params: {'field': field});

  static String? multiSelect(Set<String> selected,
          {String field = 'Options'}) =>
      ValidationEngine.validate(
        'multiSelect',
        null,
        params: {'field': field, 'selected': selected},
      );
}
