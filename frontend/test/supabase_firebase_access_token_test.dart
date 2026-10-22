import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/auth/verification_lifecycle.dart';
import 'package:medibond/core/enums/user_type.dart';
import 'package:medibond/core/supabase/supabase_bootstrap.dart';

void main() {
  tearDown(SupabaseBootstrap.resetForTesting);

  test('bootstrap supplies the Firebase ID token when one is ready', () async {
    SupabaseBootstrap.debugAccessTokenOverride = () async => 'firebase-id-token';
    expect(await SupabaseBootstrap.currentFirebaseAccessToken(), 'firebase-id-token');
    final source = File('lib/core/supabase/supabase_bootstrap.dart').readAsStringSync();
    expect(source, contains('accessToken: currentFirebaseAccessToken'));
  });

  test('bootstrap access token is null when no override and Firebase is not started', () async {
    expect(await SupabaseBootstrap.currentFirebaseAccessToken(), isNull);
    expect(await SupabaseBootstrap.refreshSession(), isNull);
  });

  test('refreshSession delegates to currentFirebaseAccessToken with forceRefresh', () async {
    SupabaseBootstrap.debugAccessTokenOverride = () async => 'refreshed-firebase-id-token';
    expect(await SupabaseBootstrap.refreshSession(), 'refreshed-firebase-id-token');
  });

  test('RoleVerificationController invokes refreshAndVerifySession on approval', () async {
    var refreshed = false;
    SupabaseBootstrap.debugAccessTokenOverride = () async {
      refreshed = true;
      return 'refreshed-on-approval-token';
    };

    RoleVerificationController.instance.setRoleState(
      UserType.doctor,
      stage: VerificationStage.verified,
    );

    expect(refreshed, isTrue);
  });

  test('FirebaseAuthService source enforces refreshAndVerifySession on login and registration', () {
    final authSource = File('lib/core/firebase/firebase_auth_service.dart').readAsStringSync();
    // Check that refreshAndVerifySession is called in signInWithEmail, signInWithMobileOtp, and registerProfile
    final occurrences = RegExp(r'SupabaseBootstrap\.refreshAndVerifySession\(forceRefresh:\s*true\)').allMatches(authSource);
    expect(occurrences.length, greaterThanOrEqualTo(3));
  });
}
