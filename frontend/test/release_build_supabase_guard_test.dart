import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Release build scripts Supabase and security guards (BLD-01)', () {
    late String ps1;
    late String sh;

    setUpAll(() {
      ps1 = File('scripts/release_build.ps1').readAsStringSync();
      sh = File('scripts/release_build.sh').readAsStringSync();
    });

    test('(a) ENABLE_SUPABASE unset omits Supabase defines and USE_SUPABASE_AUTH is never used', () {
      expect(ps1.contains('--dart-define=USE_SUPABASE_AUTH'), isFalse);
      expect(sh.contains('--dart-define=USE_SUPABASE_AUTH'), isFalse);

      expect(ps1.contains("ENABLE_SUPABASE -eq '1'"), isTrue);
      expect(sh.contains('ENABLE_SUPABASE'), isTrue);
      expect(sh.contains('== "1"'), isTrue);

      final ps1Maps = ps1.indexOf("foreach (\$name in @('GOOGLE_MAPS_API_KEY'");
      final ps1SupabaseGate = ps1.indexOf("ENABLE_SUPABASE -eq '1'");
      final ps1SupabaseDefine = ps1.indexOf('--dart-define=SUPABASE_URL=');
      expect(ps1Maps, greaterThan(0));
      expect(ps1SupabaseGate, greaterThan(ps1Maps));
      expect(ps1SupabaseDefine, greaterThan(ps1SupabaseGate));

      final shMaps = sh.indexOf('GOOGLE_MAPS_API_KEY');
      final shGate = sh.indexOf('ENABLE_SUPABASE:-}" == "1"');
      final shUrlDefine = sh.indexOf('dart-define=SUPABASE_URL');
      expect(shMaps, greaterThan(0));
      expect(shGate, greaterThan(shMaps));
      expect(shUrlDefine, greaterThan(shGate));
    });

    test('(b) ENABLE_SUPABASE=1 requires SUPABASE_URL and SUPABASE_ANON_KEY or aborts', () {
      // PowerShell script asserts URL and ANON presence before injecting defines
      expect(ps1.contains('Missing required environment variable: SUPABASE_URL'), isTrue);
      expect(ps1.contains('Missing required environment variable: SUPABASE_ANON_KEY'), isTrue);

      // Bash script asserts URL and ANON presence before injecting defines
      expect(sh.contains('Missing required environment variable: SUPABASE_URL'), isTrue);
      expect(sh.contains('Missing required environment variable: SUPABASE_ANON_KEY'), isTrue);
    });

    test('(c) SUPABASE_SERVICE_ROLE_KEY leakage guard aborts release build with security error', () {
      // PowerShell script throws security error
      expect(
        ps1.contains('SUPABASE_SERVICE_ROLE_KEY detected in environment'),
        isTrue,
        reason: 'release_build.ps1 must abort if SUPABASE_SERVICE_ROLE_KEY is present',
      );

      // Bash script prints security error and exits with code 1
      expect(
        sh.contains('SUPABASE_SERVICE_ROLE_KEY detected in environment'),
        isTrue,
        reason: 'release_build.sh must abort if SUPABASE_SERVICE_ROLE_KEY is present',
      );
    });
  });
}
