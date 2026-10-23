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

    test('(d) DEBUG_TOKEN leakage guard aborts release build with security error', () {
      expect(
        ps1.contains('DEBUG_TOKEN') && ps1.contains('SECURITY ERROR'),
        isTrue,
        reason: 'release_build.ps1 must abort if any DEBUG_TOKEN is present',
      );
      expect(
        sh.contains('DEBUG_TOKEN') && sh.contains('SECURITY ERROR'),
        isTrue,
        reason: 'release_build.sh must abort if any DEBUG_TOKEN is present',
      );
      expect(
        ps1.contains('Configured Dart define keys:'),
        isTrue,
        reason: 'release_build.ps1 must print configured dart-define key names',
      );
      expect(
        sh.contains('Configured Dart define keys:'),
        isTrue,
        reason: 'release_build.sh must print configured dart-define key names',
      );
    });
  });

  group('Behavioral Release Build Process Execution Tests (--dry-run)', () {
    bool isBashAvailable() {
      try {
        final res = Process.runSync('bash', ['-c', 'echo ready']);
        return res.exitCode == 0 && res.stdout.toString().contains('ready');
      } catch (_) {
        return false;
      }
    }

    bool isPowershellAvailable() {
      try {
        final cmd = Platform.isWindows ? 'powershell' : 'pwsh';
        final res = Process.runSync(cmd, ['-NoProfile', '-Command', 'echo ready']);
        return res.exitCode == 0 && res.stdout.toString().contains('ready');
      } catch (_) {
        return false;
      }
    }

    test('PowerShell release_build.ps1 behavioral test', () async {
      if (!isPowershellAvailable()) {
        print('Skipping [PowerShell release_build.ps1 behavioral test]: powershell/pwsh is not available on this platform');
        return;
      }

      final pwshCmd = Platform.isWindows ? 'powershell' : 'pwsh';
      final baseEnv = {
        'FIREBASE_API_KEY_ANDROID': 'dummy_android_key_123',
        'ENABLE_SUPABASE': '',
        'SUPABASE_URL': '',
        'SUPABASE_ANON_KEY': '',
        'SUPABASE_SERVICE_ROLE_KEY': '',
      };

      // (a) ENABLE_SUPABASE unset -> exit 0 and output does NOT contain SUPABASE_URL
      final resA = await Process.run(
        pwshCmd,
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'scripts/release_build.ps1', '-DryRun'],
        environment: baseEnv,
      );
      expect(resA.exitCode, 0, reason: 'Script must succeed with code 0 on valid dry-run: ${resA.stderr}');
      expect(resA.stdout.toString().contains('--dart-define=SUPABASE_URL='), isFalse, reason: 'SUPABASE_URL define must not be injected when unset');

      // (b) ENABLE_SUPABASE=1 and SUPABASE_URL missing -> non-zero exit
      final resB = await Process.run(
        pwshCmd,
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'scripts/release_build.ps1', '-DryRun'],
        environment: {
          ...baseEnv,
          'ENABLE_SUPABASE': '1',
          'SUPABASE_URL': '',
          'SUPABASE_ANON_KEY': '',
        },
      );
      expect(resB.exitCode, isNot(0), reason: 'Missing SUPABASE_URL must fail with non-zero exit');

      // (c) SUPABASE_SERVICE_ROLE_KEY present -> non-zero exit
      final resC = await Process.run(
        pwshCmd,
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'scripts/release_build.ps1', '-DryRun'],
        environment: {
          ...baseEnv,
          'SUPABASE_SERVICE_ROLE_KEY': 'leak_service_role_key_value',
        },
      );
      expect(resC.exitCode, isNot(0), reason: 'SUPABASE_SERVICE_ROLE_KEY leakage must fail with non-zero exit');

      // (d) APP_CHECK_DEBUG_TOKEN passed as dart-define -> non-zero exit
      final resD = await Process.run(
        pwshCmd,
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'scripts/release_build.ps1', '-DryRun', '--dart-define=APP_CHECK_DEBUG_TOKEN=leak_debug_token_value_abc'],
        environment: baseEnv,
      );
      expect(resD.exitCode, isNot(0), reason: 'APP_CHECK_DEBUG_TOKEN leakage must fail with non-zero exit');
      expect(
        resD.stderr.toString().contains('SECURITY ERROR: Debug token') ||
            resD.stdout.toString().contains('SECURITY ERROR: Debug token'),
        isTrue,
        reason: 'Error message must explicitly mention debug token security error',
      );
    });

    test('Bash release_build.sh behavioral test', () async {
      if (!isBashAvailable()) {
        print('Skipping [Bash release_build.sh behavioral test]: bash is not available or non-functional on this platform');
        return;
      }

      final baseEnv = {
        'FIREBASE_API_KEY_ANDROID': 'dummy_android_key_123',
        'ENABLE_SUPABASE': '',
        'SUPABASE_URL': '',
        'SUPABASE_ANON_KEY': '',
        'SUPABASE_SERVICE_ROLE_KEY': '',
      };

      // (a) ENABLE_SUPABASE unset -> exit 0 and output does NOT contain SUPABASE_URL
      final resA = await Process.run(
        'bash',
        ['scripts/release_build.sh', '--dry-run'],
        environment: baseEnv,
      );
      expect(resA.exitCode, 0, reason: 'Script must succeed with code 0 on valid dry-run: ${resA.stderr}');
      expect(resA.stdout.toString().contains('--dart-define=SUPABASE_URL='), isFalse, reason: 'SUPABASE_URL define must not be injected when unset');

      // (b) ENABLE_SUPABASE=1 and SUPABASE_URL missing -> non-zero exit
      final resB = await Process.run(
        'bash',
        ['scripts/release_build.sh', '--dry-run'],
        environment: {
          ...baseEnv,
          'ENABLE_SUPABASE': '1',
          'SUPABASE_URL': '',
          'SUPABASE_ANON_KEY': '',
        },
      );
      expect(resB.exitCode, isNot(0), reason: 'Missing SUPABASE_URL must fail with non-zero exit');

      // (c) SUPABASE_SERVICE_ROLE_KEY present -> non-zero exit
      final resC = await Process.run(
        'bash',
        ['scripts/release_build.sh', '--dry-run'],
        environment: {
          ...baseEnv,
          'SUPABASE_SERVICE_ROLE_KEY': 'leak_service_role_key_value',
        },
      );
      expect(resC.exitCode, isNot(0), reason: 'SUPABASE_SERVICE_ROLE_KEY leakage must fail with non-zero exit');

      // (d) APP_CHECK_DEBUG_TOKEN passed as dart-define -> non-zero exit
      final resD = await Process.run(
        'bash',
        ['scripts/release_build.sh', '--dry-run', '--dart-define=APP_CHECK_DEBUG_TOKEN=leak_debug_token_value_abc'],
        environment: baseEnv,
      );
      expect(resD.exitCode, isNot(0), reason: 'APP_CHECK_DEBUG_TOKEN leakage must fail with non-zero exit');
      expect(
        resD.stderr.toString().contains('SECURITY ERROR: Debug token') ||
            resD.stdout.toString().contains('SECURITY ERROR: Debug token'),
        isTrue,
        reason: 'Error message must explicitly mention debug token security error',
      );
    });
  });
}
