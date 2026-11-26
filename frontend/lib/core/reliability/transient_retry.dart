import 'dart:async';
import 'dart:math';

import 'supabase_error_classifier.dart';

typedef TransientRetryOperation<T> = Future<T> Function();

/// Bounded exponential backoff for transient client failures (REL-02).
Future<T> runWithTransientRetry<T>(
  TransientRetryOperation<T> operation, {
  int maxAttempts = 3,
  Duration baseDelay = const Duration(milliseconds: 200),
  Duration maxDelay = const Duration(seconds: 4),
}) async {
  var attempt = 0;
  final rng = Random();
  while (true) {
    attempt++;
    try {
      return await operation();
    } catch (e) {
      final isLast = attempt >= maxAttempts;
      if (isLast || !SupabaseErrorClassifier.isTransient(e)) {
        rethrow;
      }
      final expMs = baseDelay.inMilliseconds * pow(2, attempt - 1);
      final capped = expMs > maxDelay.inMilliseconds ? maxDelay.inMilliseconds : expMs.toInt();
      final jitter = (capped * 0.25 * rng.nextDouble()).round();
      await Future<void>.delayed(Duration(milliseconds: capped + jitter));
    }
  }
}