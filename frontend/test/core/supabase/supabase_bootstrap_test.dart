import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/supabase/supabase_bootstrap.dart';

void main() {
  setUp(() {
    SupabaseBootstrap.resetForTesting();
  });

  tearDown(() {
    SupabaseBootstrap.resetForTesting();
  });

  group('SupabaseBootstrap No-Config & Lifecycle Tests', () {
    test('hasConfig is false when compile-time defines are absent', () {
      expect(SupabaseBootstrap.hasConfig, isFalse);
    });

    test('initialize() is a safe no-op returning false when config is absent',
        () async {
      final result = await SupabaseBootstrap.initialize();

      expect(result, isFalse);
      expect(SupabaseBootstrap.isReady, isFalse);
      expect(SupabaseBootstrap.lastInitError, contains('missing'));
    });

    test('initialize() does not throw even with empty explicit strings',
        () async {
      final result = await SupabaseBootstrap.initialize(url: '', anonKey: '');

      expect(result, isFalse);
      expect(SupabaseBootstrap.isReady, isFalse);
    });

    test('client getter throws StateError when SupabaseBootstrap is not ready',
        () {
      expect(
        () => SupabaseBootstrap.client,
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Supabase has not been initialized'),
        )),
      );
    });
  });
}
