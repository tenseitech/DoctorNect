import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/auth/mobile_registration_lookup.dart';
import 'package:medibond/core/auth/unified_auth_flow_controller.dart';
import 'package:medibond/core/enums/user_type.dart';

void main() {
  test('server role strings for the five demo accounts map to the right modules', () {
    expect(MobileRegistrationLookup.parseUserType('doctor'), UserType.doctor);
    expect(MobileRegistrationLookup.parseUserType('patient'), UserType.patient);
    expect(MobileRegistrationLookup.parseUserType('medicalStore'), UserType.medicalStore);
    expect(MobileRegistrationLookup.parseUserType('pharmacy'), UserType.medicalStore);
    expect(MobileRegistrationLookup.parseUserType('lab'), UserType.lab);
    expect(MobileRegistrationLookup.parseUserType('ambulance'), UserType.ambulance);
  });

  test('existing account without a server role is not signed in as patient', () {
    expect(loginRoleFromServer(null), isNull);
    for (final r in [UserType.doctor, UserType.medicalStore, UserType.lab, UserType.ambulance]) {
      expect(loginRoleFromServer(r), r);
    }
  });

  test('profile repository accepts the same pharmacy aliases as the OTP lookup', () {
    final src = File('lib/core/supabase/repositories/supabase_user_repository.dart').readAsStringSync();
    expect(src, contains("'medical' || 'medicalStore' || 'medical_store' || 'pharmacy'"));
  });

  test('staging demo APK enables the ambulance module (demo 9999900005)', () {
    final s = File('scripts/build_staging_demo_apk.ps1').readAsStringSync();
    expect(s, contains('--dart-define=AMBULANCE_ENABLED=true'));
  });
}
