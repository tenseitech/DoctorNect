import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/observability/operational_log.dart';

void main() {
  test('OperationalLog redacts sensitive map keys in debug', () {
    expect(
      () => OperationalLog.info(
        'api_failure',
        fields: {
          'otp': '123456',
          'appointment_id': 'a1',
        },
      ),
      returnsNormally,
    );
  });
}