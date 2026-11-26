import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/reliability/in_flight_guard.dart';

/// Regression for Audit 6/8 duplicate booking submits (client-side guard convention).
void main() {
  test('QA-BOOK-01 concurrent book_appointment guard rejects duplicate', () async {
    final guard = InFlightGuard();
    const appointmentId = 'appt-regression-001';
    final key = 'book_appointment:$appointmentId';
    final gate = Completer<void>();

    final inFlight = guard.run(key, () async {
      await gate.future;
      return <String, dynamic>{'ok': true};
    });

    await expectLater(
      guard.run(key, () async => <String, dynamic>{}),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Operation already in progress'),
        ),
      ),
    );

    gate.complete();
    final result = await inFlight;
    expect(result['ok'], isTrue);
    expect(guard.tryAcquire(key), isTrue);
  });
}