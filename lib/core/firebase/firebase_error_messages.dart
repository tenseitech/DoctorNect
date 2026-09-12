import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

bool _isGenericMessage(String? message) {
  if (message == null) return true;
  final normalized = message.trim().toLowerCase();
  if (normalized.isEmpty) return true;
  return normalized == 'error' ||
      normalized == 'unknown' ||
      normalized == 'unknown error' ||
      normalized == 'internal' ||
      normalized == 'internal error' ||
      normalized.startsWith('firebase: error');
}

bool _isReferrerBlocked(FirebaseAuthException error) {
  final code = error.code.toLowerCase();
  if (code.contains('requests-from-referer') || code.contains('are-blocked')) {
    return true;
  }
  final message = error.message?.toLowerCase() ?? '';
  return message.contains('requests-from-referer') ||
      message.contains('are-blocked');
}

String describeFirebaseAuthError(
  FirebaseAuthException error, {
  String fallback = 'Sign-in failed. Please try again.',
}) {
  if (_isReferrerBlocked(error)) {
    return 'This website is not allowed to use Firebase yet. '
        'Add medibond-45fad.web.app to the Firebase Web API key '
        'referrer list in Google Cloud Console.';
  }

  final mapped = switch (error.code) {
    'user-not-found' ||
    'wrong-password' ||
    'invalid-credential' =>
      'Invalid email or password',
    'email-already-in-use' => 'An account already exists with this email',
    'weak-password' => 'Password is too weak',
    'invalid-email' => 'Invalid email address',
    'too-many-requests' => 'Too many attempts. Try again later.',
    'account-exists-with-different-credential' =>
      'This email is registered with a different sign-in method',
    'popup-closed-by-user' ||
    'cancelled-popup-request' ||
    'web-context-cancelled' =>
      'Sign-in cancelled',
    'operation-not-allowed' =>
      'This sign-in method is not enabled in Firebase. Contact support.',
    'network-request-failed' =>
      'Network error. Check your internet connection and try again.',
    'internal-error' =>
      error.message != null && error.message!.isNotEmpty && !error.message!.toLowerCase().contains('internal-error')
          ? error.message!.trim()
          : 'Sign-in service error. Check Firebase Authentication settings.',
    'invalid-api-key' ||
    'api-key-not-valid.-please-pass-a-valid-api-key.' =>
      'App configuration error. Redeploy the latest web build.',
    'app-not-authorized' =>
      'This app is not authorized for Firebase. Contact support.',
    'user-disabled' =>
      'This account has been disabled. Contact support.',
    'requires-recent-login' =>
      'For security, sign out and sign in again, then retry.',
    _ => null,
  };
  if (mapped != null) return mapped;
  if (!_isGenericMessage(error.message)) return error.message!.trim();
  return '$fallback (${error.code})';
}

String describeFirebaseError(
  FirebaseException error, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  if (kDebugMode) {
    debugPrint(
      'Firebase error [${error.code}]: ${error.message ?? '(no message)'}',
    );
  }

  // Prefer caller fallback for known Firestore codes so action-specific messages
  // (accept, cancel, reschedule, etc.) reach the user instead of raw codes.
  final useFallback = switch (error.code) {
    'permission-denied' ||
    'unavailable' ||
    'unauthenticated' ||
    'not-found' ||
    'failed-precondition' ||
    'resource-exhausted' ||
    'deadline-exceeded' ||
    'cancelled' ||
    'network-request-failed' ||
    'aborted' ||
    'internal' =>
      true,
    _ => false,
  };
  if (useFallback) return fallback;

  if (!_isGenericMessage(error.message)) return error.message!.trim();
  return fallback;
}

String describeUserFacingError(
  Object error, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  if (error is FirebaseAuthException) {
    return describeFirebaseAuthError(error, fallback: fallback);
  }
  if (error is FirebaseException) {
    return describeFirebaseError(error, fallback: fallback);
  }
  final text = error.toString().trim();
  if (_isGenericMessage(text)) return fallback;
  return text;
}
