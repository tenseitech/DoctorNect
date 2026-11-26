import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// D1(a): after completeAmbulanceMobileOtpLogin the server changes the session's custom claims
/// (demo-plane marker for the demo ambulance). The client must force a fresh ID token before
/// its next request, otherwise the cached token routes to the wrong data plane.
void main() {
  test('ambulance OTP login refreshes the ID token before any data call', () {
    final src = File('lib/core/firebase/repositories/ambulance_repository.dart')
        .readAsStringSync();
    final call = src.indexOf("'completeAmbulanceMobileOtpLogin'");
    expect(call, greaterThan(0));
    final refresh =
        src.indexOf('AmbulanceAuthHelper.refreshCallableAuthToken()', call);
    final firstDataCall = src.indexOf('await linkDriverAuth(driverId);', call);
    expect(refresh, greaterThan(call));
    expect(firstDataCall, greaterThan(refresh));
  });

  test('refreshCallableAuthToken forces a token refresh', () {
    final helper =
        File('lib/core/firebase/ambulance_auth_helper.dart').readAsStringSync();
    final start =
        helper.indexOf('static Future<bool> refreshCallableAuthToken');
    expect(start, greaterThan(0));
    expect(helper.indexOf('getIdToken(true)', start), greaterThan(start));
  });
}
