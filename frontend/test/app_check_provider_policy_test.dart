import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/auth/registration_otp_service.dart';
import 'package:medibond/core/security/app_check_provider_policy.dart';
import 'package:medibond/core/security/app_check_service.dart';

AppCheckProviderKind _resolve({
  bool debug = false,
  bool hasEnv = false,
  String env = '',
  bool flag = false,
}) =>
    AppCheckProviderPolicy.resolve(
      isDebugMode: debug,
      hasAppEnv: hasEnv,
      appEnv: env,
      debugProviderRequested: flag,
    );

void main() {
  group('AppCheckProviderPolicy', () {
    test('production never uses the debug provider, in any build mode', () {
      for (final debug in [false, true]) {
        expect(
          _resolve(debug: debug, hasEnv: true, env: 'production'),
          AppCheckProviderKind.platformAttestation,
        );
      }
    });

    test('production build that requests the debug provider fails hard', () {
      expect(
        () => _resolve(hasEnv: true, env: 'production', flag: true),
        throwsStateError,
      );
      expect(
        () =>
            _resolve(debug: true, hasEnv: true, env: 'PRODUCTION', flag: true),
        throwsStateError,
      );
    });

    test('release build defaults to platform attestation', () {
      expect(_resolve(), AppCheckProviderKind.platformAttestation);
      expect(_resolve(hasEnv: true, env: 'staging'),
          AppCheckProviderKind.platformAttestation);
    });

    test('release build needs explicit APP_ENV=staging AND the flag', () {
      expect(_resolve(flag: true), AppCheckProviderKind.platformAttestation,
          reason:
              'flag without explicit APP_ENV must not enable debug provider');
      expect(_resolve(hasEnv: true, env: 'staging', flag: true),
          AppCheckProviderKind.debug);
    });

    test('debug mode may use the debug provider outside production', () {
      expect(_resolve(debug: true), AppCheckProviderKind.debug);
      expect(_resolve(debug: true, hasEnv: true, env: 'staging'),
          AppCheckProviderKind.debug);
    });

    test('this test run (no dart-defines) resolves without throwing', () {
      expect(() => AppCheckProviderPolicy.current(), returnsNormally);
    });
  });

  group('build wiring', () {
    test('firebase_bootstrap selects the provider only through the policy', () {
      final src =
          File('lib/core/firebase/firebase_bootstrap.dart').readAsStringSync();
      expect(src, contains('AppCheckProviderPolicy.current()'));
      expect(src, isNot(contains('kDebugMode || debugToken.isNotEmpty')),
          reason:
              'a debug token alone must not switch release to debug provider');
    });

    test('release build scripts reject the debug provider flag', () {
      for (final path in [
        'scripts/release_build.ps1',
        'scripts/release_build.sh'
      ]) {
        final src = File(path).readAsStringSync();
        final allow = RegExp(r'allowed(DefineKeys|_keys)=?\s*=?\s*[@(][^)]*\)')
            .firstMatch(src)
            ?.group(0);
        expect(allow, isNotNull,
            reason: '$path must keep a dart-define allowlist');
        expect(allow, isNot(contains('APP_CHECK_DEBUG_PROVIDER')),
            reason: path);
        expect(allow, isNot(contains('DEBUG_TOKEN')), reason: path);
      }
    });
  });

  group('App Check rejection messages', () {
    test('missing token (sideloaded build) is distinguished', () {
      final r = RegistrationOtpService.appCheckRejectionReason(
          hasToken: false, tokenFailureReason: 'attestation_failed');
      expect(r, 'app_check_token_missing');
      expect(RegistrationOtpService.appCheckRejectionMessage(r),
          allOf(contains('Google Play'), contains('app_check_token_missing')));
    });

    test('rate limited and rejected tokens get their own codes', () {
      expect(
          RegistrationOtpService.appCheckRejectionReason(
              hasToken: false, tokenFailureReason: 'rate_limited'),
          'app_check_rate_limited');
      expect(RegistrationOtpService.appCheckRejectionReason(hasToken: true),
          'app_check_token_rejected');
    });

    test('failure classification never echoes input', () {
      const secretish = 'AppCheck failed: 403 attestation failed token=abc123';
      final code = AppCheckService.classifyFailure(Exception(secretish));
      expect(code, 'attestation_failed');
      expect(code, isNot(contains('abc123')));
      expect(AppCheckService.classifyFailure(Exception('Too many attempts')),
          'rate_limited');
    });
  });
}
