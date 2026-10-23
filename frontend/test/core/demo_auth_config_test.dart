import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/auth/demo_auth_config.dart';
import 'package:medibond/core/enums/user_type.dart';
import 'package:medibond/core/firebase/repositories/doctor_verification_repository.dart';

void main() {
  tearDown(() {
    DemoAuthConfig.debugReleaseModeOverride = null;
  });

  group('DemoAuthConfig - Release Mode Gating via debugReleaseModeOverride', () {
    test('when debugReleaseModeOverride is true, isDemoAllowed is strictly false', () {
      DemoAuthConfig.debugReleaseModeOverride = true;
      expect(DemoAuthConfig.isDemoAllowed, isFalse);
    });

    test('when debugReleaseModeOverride is true, all demo phone checks return false', () {
      DemoAuthConfig.debugReleaseModeOverride = true;

      // Doctor
      expect(DemoAuthConfig.isDemoDoctorPhone('9999900002'), isFalse);
      expect(DemoAuthConfig.isDemoDoctorPhone('+919999900002'), isFalse);
      expect(DemoAuthConfig.isDemoDoctorId('9999900002'), isFalse);
      expect(DemoAuthConfig.isDemoDoctorId('d_9999900002'), isFalse);

      // Pharmacy
      expect(DemoAuthConfig.isDemoPharmacyPhone('9999900003'), isFalse);
      expect(DemoAuthConfig.isDemoPharmacyPhone('+919999900003'), isFalse);
      expect(DemoAuthConfig.isDemoPharmacyId('9999900003'), isFalse);

      // Lab
      expect(DemoAuthConfig.isDemoLabPhone('9999900004'), isFalse);
      expect(DemoAuthConfig.isDemoLabPhone('+919999900004'), isFalse);
      expect(DemoAuthConfig.isDemoLabId('9999900004'), isFalse);

      // Ambulance
      expect(DemoAuthConfig.isDemoAmbulancePhone('9999900005'), isFalse);
      expect(DemoAuthConfig.isDemoAmbulancePhone('+919999900005'), isFalse);
      expect(DemoAuthConfig.isDemoAmbulanceId('9999900005'), isFalse);

      // Patient
      expect(DemoAuthConfig.isDemoPatientPhone('9999900001'), isFalse);
      expect(DemoAuthConfig.isDemoPatientPhone('+919999900001'), isFalse);

      // Super Admin
      expect(DemoAuthConfig.isDemoSuperAdminPhone('9999988888'), isFalse);

      // Aggregates
      expect(DemoAuthConfig.isAnyDemoPhone('9999900002'), isFalse);
      expect(DemoAuthConfig.roleForDemoPhone('9999900002'), isNull);

      for (final role in UserType.values) {
        expect(DemoAuthConfig.isDemoRolePhone(role, '9999900002'), isFalse);
      }
    });

    test('DoctorVerificationRepository does not bypass verification in release mode', () {
      DemoAuthConfig.debugReleaseModeOverride = true;

      // In release mode, data with demo phone must NOT be auto-verified
      expect(
        DoctorVerificationRepository.parseVerifiedFromDoctorData({
          'mobile': '9999900002',
          'verified': false,
        }),
        isFalse,
      );
      expect(
        DoctorVerificationRepository.parseVerifiedFromDoctorData({
          'doctorId': '9999900002',
          'verified': false,
        }),
        isFalse,
      );
      expect(
        DoctorVerificationRepository.parseVerifiedFromDoctorData({
          'doctorId': 'd_9999900002',
          'verified': false,
        }),
        isFalse,
      );
    });

    test('in debug mode (debugReleaseModeOverride = false), demo phones are recognized', () {
      DemoAuthConfig.debugReleaseModeOverride = false;
      expect(DemoAuthConfig.isDemoAllowed, isTrue);

      expect(DemoAuthConfig.isDemoDoctorPhone('9999900002'), isTrue);
      expect(DemoAuthConfig.isDemoDoctorPhone('+91 99999 00002'), isTrue);
      expect(DemoAuthConfig.isDemoPharmacyPhone('9999900003'), isTrue);
      expect(DemoAuthConfig.isDemoLabPhone('9999900004'), isTrue);
      expect(DemoAuthConfig.isDemoAmbulancePhone('9999900005'), isTrue);
      expect(DemoAuthConfig.isDemoPatientPhone('9999900001'), isTrue);

      // Non-demo numbers are not matched
      expect(DemoAuthConfig.isDemoDoctorPhone('9876543210'), isFalse);
    });

    test('loose substring checks are blocked even in debug mode', () {
      DemoAuthConfig.debugReleaseModeOverride = false;

      // Attacker doctorId containing demoDoctorPhone as substring must NOT match
      expect(DemoAuthConfig.isDemoDoctorId('hacker_9999900002_attack'), isFalse);
      expect(DemoAuthConfig.isDemoPharmacyId('store_9999900003_extra'), isFalse);
      expect(DemoAuthConfig.isDemoLabId('lab_9999900004_extra'), isFalse);
      expect(DemoAuthConfig.isDemoAmbulanceId('amb_9999900005_extra'), isFalse);
    });
  });
}
