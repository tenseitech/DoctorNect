import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/reliability/in_flight_guard.dart';
import 'package:medibond/core/reliability/supabase_error_classifier.dart';
import 'package:medibond/core/reliability/transient_retry.dart';

void main() {
  test('SupabaseErrorClassifier detects transient network errors', () {
    expect(SupabaseErrorClassifier.isTransient(Exception('SocketException: timeout')), isTrue);
    expect(SupabaseErrorClassifier.isTransient(Exception('PostgrestException code: 503')), isTrue);
    expect(SupabaseErrorClassifier.isTransient(Exception('PostgrestException code: 403')), isFalse);
  });

  test('runWithTransientRetry succeeds after transient failure', () async {
    var calls = 0;
    final value = await runWithTransientRetry(() async {
      calls++;
      if (calls < 2) throw Exception('SocketException: connection reset');
      return 'ok';
    }, maxAttempts: 3, baseDelay: Duration.zero, maxDelay: Duration.zero);
    expect(value, 'ok');
    expect(calls, 2);
  });

  test('runWithTransientRetry does not retry permanent errors', () async {
    var calls = 0;
    await expectLater(
      runWithTransientRetry(() async {
        calls++;
        throw Exception('PostgrestException code: 400 invalid');
      }, maxAttempts: 3, baseDelay: Duration.zero, maxDelay: Duration.zero),
      throwsA(isA<Exception>()),
    );
    expect(calls, 1);
  });

  test('InFlightGuard blocks duplicate operations', () async {
    final guard = InFlightGuard();
    expect(guard.tryAcquire('save_1'), isTrue);
    expect(guard.tryAcquire('save_1'), isFalse);
    guard.release('save_1');
    expect(guard.tryAcquire('save_1'), isTrue);
  });

  test('InFlightGuard releases after exception', () async {
    final guard = InFlightGuard();
    await expectLater(
      guard.run('op_a', () async {
        throw StateError('boom');
      }),
      throwsA(isA<StateError>()),
    );
    expect(guard.tryAcquire('op_a'), isTrue);
  });

  test('InFlightGuard.run rejects concurrent duplicate', () async {
    final guard = InFlightGuard();
    final gate = Completer<void>();
    final first = guard.run('concurrent_x', () async {
      await gate.future;
      return 1;
    });
    await expectLater(
      guard.run('concurrent_x', () async => 2),
      throwsA(isA<StateError>()),
    );
    gate.complete();
    expect(await first, 1);
  });
}