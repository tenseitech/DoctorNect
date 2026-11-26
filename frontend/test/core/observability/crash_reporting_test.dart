import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/observability/crash_reporting.dart';

void main() {
  test('configure completes when Firebase is not initialized', () async {
    expect(CrashReporting.isSupported, isTrue);
    await expectLater(CrashReporting.configure(), completes);
  });
}