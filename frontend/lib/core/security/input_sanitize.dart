/// Shared client-side input sanitization (mirrors functions/input_sanitize.js).
/// Rejects control chars / script payloads; does not replace server validation.
abstract final class InputSanitize {
  static const maxReviewLength = 500;
  static const maxAdTitleLength = 80;
  static const maxAdDescriptionLength = 500;
  static const maxMessageLength = 2000;
  static const maxLocationLength = 200;
  static const maxPdfBytes = 15 * 1024 * 1024;
  static const maxImageBytes = 5 * 1024 * 1024;

  static final RegExp _controlChars = RegExp(
    r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]',
  );

  static String stripControlChars(String value) =>
      value.replaceAll(_controlChars, '');

  /// Plain text for Firestore / UI — no HTML/script schemes.
  static String plainText(String? value, {int maxLength = maxMessageLength}) {
    var s = stripControlChars(value ?? '').trim();
    s = s.replaceAll(RegExp(r'[<>]'), '');
    s = s.replaceAll(RegExp(r'javascript\s*:', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'data\s*:', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'vbscript\s*:', caseSensitive: false), '');
    if (s.length > maxLength) s = s.substring(0, maxLength);
    return s;
  }

  static String? validatePlainText(
    String? value, {
    required String field,
    int minLength = 1,
    int maxLength = maxMessageLength,
  }) {
    final s = plainText(value, maxLength: maxLength);
    if (s.length < minLength) return '$field is required';
    if ((value ?? '').trim().length > maxLength) {
      return '$field must be at most $maxLength characters';
    }
    return null;
  }

  /// Safe Storage object name (no path traversal).
  static String fileName(String? name, {String fallback = 'file'}) {
    final base = (name ?? fallback).split(RegExp(r'[/\\]')).last;
    var clean = stripControlChars(base).replaceAll(RegExp(r'[^\w.\-]'), '_');
    clean = clean.replaceFirst(RegExp(r'^\.+'), '');
    if (clean.isEmpty || clean == '.' || clean == '..') clean = fallback;
    if (clean.length > 120) {
      final extMatch = RegExp(r'(\.[A-Za-z0-9]{1,8})$').firstMatch(clean);
      final ext = extMatch?.group(1) ?? '';
      clean = '${clean.substring(0, 120 - ext.length)}$ext';
    }
    return clean;
  }

  static bool isAllowedPdf(String fileName) =>
      fileName.toLowerCase().endsWith('.pdf');

  static bool isAllowedImage(String fileName) {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp');
  }

  static String? validateUploadBytes({
    required int byteLength,
    required int maxBytes,
    String field = 'File',
  }) {
    if (byteLength <= 0) return '$field is empty';
    if (byteLength > maxBytes) {
      final mb = (maxBytes / (1024 * 1024)).toStringAsFixed(0);
      return '$field must be under ${mb}MB';
    }
    return null;
  }

  static bool isAllowedLaunchUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'https' ||
        scheme == 'http' ||
        scheme == 'tel' ||
        scheme == 'mailto' ||
        scheme == 'sms') {
      return true;
    }
    // Allow in-app relative paths only when host is empty.
    if (scheme.isEmpty && uri.path.isNotEmpty) return true;
    return false;
  }
}
