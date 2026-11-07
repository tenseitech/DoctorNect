import 'package:flutter/material.dart';

import '../config/firestore_forbidden_guard.dart';

/// User-visible handling when release build blocks client Firestore.
abstract final class FirestoreUi {
  static const userMessage =
      'This section is temporarily unavailable. Please try again or update the app.';

  static T? guardSync<T>(T Function() run, {void Function(String message)? showError}) {
    try {
      return run();
    } on StateError catch (e) {
      if (!e.message.contains('FIRESTORE_FORBIDDEN')) rethrow;
      showError?.call(userMessage);
      return null;
    }
  }

  static Future<T?> guardAsync<T>(
    Future<T> Function() run, {
    void Function(String message)? showError,
  }) async {
    try {
      return await run();
    } on StateError catch (e) {
      if (!e.message.contains('FIRESTORE_FORBIDDEN')) rethrow;
      showError?.call(userMessage);
      return null;
    }
  }

  static void showSnack(BuildContext context, [String? message]) {
    final text = message ?? userMessage;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @visibleForTesting
  static bool get isForbiddenActive => FirestoreForbiddenGuard.isForbidden;
}
