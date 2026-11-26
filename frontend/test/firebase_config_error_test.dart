import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/firebase/firebase_bootstrap.dart';
import 'package:medibond/firebase_options.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    DefaultFirebaseOptions.debugApiKeyOverride = null;
    FirebaseBootstrap.resetForTesting();
  });

  test('missing Firebase API key: friendly message + reason code, no raw text', () async {
    DefaultFirebaseOptions.debugApiKeyOverride = '';
    expect(DefaultFirebaseOptions.isConfigured, isFalse);

    final ok = await FirebaseBootstrap.initialize();

    expect(ok, isFalse);
    expect(FirebaseBootstrap.isReady, isFalse);
    expect(FirebaseBootstrap.lastInitReasonCode, FirebaseBootstrap.configMissingReasonCode);
    expect(FirebaseBootstrap.lastInitError, FirebaseBootstrap.configMissingUserMessage);
    expect(FirebaseBootstrap.lastInitError, isNot(contains('API key')));
    expect(FirebaseBootstrap.lastInitError, isNot(contains('Firebase')));
  });

  test('API key present: no config error is reported', () {
    DefaultFirebaseOptions.debugApiKeyOverride = 'present-in-build';
    expect(DefaultFirebaseOptions.isConfigured, isTrue);
    expect(FirebaseBootstrap.lastInitReasonCode, isNull);
  });

  test('required client define names match what the build scripts pass', () {
    expect(DefaultFirebaseOptions.requiredClientDefines, isNotEmpty);
    final staging = File('scripts/build_staging_demo_apk.ps1').readAsStringSync();
    final releasePs = File('scripts/release_build.ps1').readAsStringSync();
    final releaseSh = File('scripts/release_build.sh').readAsStringSync();
    for (final name in ['FIREBASE_API_KEY_ANDROID', 'FIREBASE_PROJECT_ID']) {
      for (final (label, src) in [('staging', staging), ('release.ps1', releasePs), ('release.sh', releaseSh)]) {
        expect(src, contains('--dart-define=$name='), reason: '$label must pass $name');
      }
    }
    final options = File('lib/firebase_options.dart').readAsStringSync();
    for (final name in ['FIREBASE_API_KEY_ANDROID', 'FIREBASE_PROJECT_ID']) {
      expect(options, contains("String.fromEnvironment('$name')"));
    }
  });

  test('staging demo APK passes the data plane and the registered App Check debug token', () {
    final staging = File('scripts/build_staging_demo_apk.ps1').readAsStringSync();
    // Without these the app signs in, finds no Supabase client and shows
    // "Account profile not found" (data plane) or fails every callable with
    // UNAUTHENTICATED after a fresh install (App Check token).
    for (final name in ['SUPABASE_URL', 'SUPABASE_ANON_KEY', 'APP_CHECK_DEBUG_TOKEN']) {
      expect(staging, contains('--dart-define=$name='), reason: 'staging must pass $name');
    }
    final constants = File('lib/core/constants/app_constants.dart').readAsStringSync();
    expect(constants, contains("'APP_CHECK_DEBUG_TOKEN'"));
  });

  test('the Firebase project never defaults to a project without Cloud Functions', () {
    final options = File('lib/firebase_options.dart').readAsStringSync();
    expect(options, isNot(contains("'medibond-staging'")));
    final gs = File('android/app/google-services.json').readAsStringSync();
    expect(gs, contains('"project_id": "medibond-45fad"'));
    expect(options, contains("_defaultProjectId = 'medibond-45fad'"));
  });
}
