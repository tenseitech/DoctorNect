import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
  });
}
