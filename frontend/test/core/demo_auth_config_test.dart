import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/auth/demo_auth_config.dart';
import 'package:medibond/core/enums/user_type.dart';
import 'package:medibond/core/firebase/repositories/doctor_verification_repository.dart';

void main() {
  tearDown(() {
    DemoAuthConfig.debugReleaseModeOverride = null;
  });

  group('DemoAuthConfig - Google Play Reviewer Accounts & Security Gating', () {
    test('Google Play Reviewer phones (9999900001-5) are recognized for role access', () {
      // Doctor reviewer
      expect(DemoAuthConfig.isDemoDoctorPhone('9999900002'), isTrue);
      expect(DemoAuthConfig.isDemoDoctorPhone('+919999900002'), isTrue);
      expect(DemoAuthConfig.isDemoDoctorId('9999900002'), isTrue);
      expect(DemoAuthConfig.isDemoDoctorId('d_9999900002'), isTrue);

      // Pharmacy reviewer
      expect(DemoAuthConfig.isDemoPharmacyPhone('9999900003'), isTrue);
      expect(DemoAuthConfig.isDemoPharmacyPhone('+919999900003'), isTrue);
      expect(DemoAuthConfig.isDemoPharmacyId('9999900003'), isTrue);

      // Lab reviewer
      expect(DemoAuthConfig.isDemoLabPhone('9999900004'), isTrue);
      expect(DemoAuthConfig.isDemoLabPhone('+919999900004'), isTrue);
      expect(DemoAuthConfig.isDemoLabId('9999900004'), isTrue);

      // Ambulance reviewer
      expect(DemoAuthConfig.isDemoAmbulancePhone('9999900005'), isTrue);
      expect(DemoAuthConfig.isDemoAmbulancePhone('+919999900005'), isTrue);
      expect(DemoAuthConfig.isDemoAmbulanceId('9999900005'), isTrue);

      // Patient reviewer
      expect(DemoAuthConfig.isDemoPatientPhone('9999900001'), isTrue);
      expect(DemoAuthConfig.isDemoPatientPhone('+919999900001'), isTrue);

      // Aggregates
      expect(DemoAuthConfig.isAnyDemoPhone('9999900002'), isTrue);
      expect(DemoAuthConfig.roleForDemoPhone('9999900002'), equals(UserType.doctor));
      expect(DemoAuthConfig.roleForDemoPhone('9999900001'), equals(UserType.patient));
      expect(DemoAuthConfig.roleForDemoPhone('9999900003'), equals(UserType.medicalStore));
      expect(DemoAuthConfig.roleForDemoPhone('9999900004'), equals(UserType.lab));
      expect(DemoAuthConfig.roleForDemoPhone('9999900005'), equals(UserType.ambulance));
    });

    test('DoctorVerificationRepository auto-verifies allowlisted reviewer doctor account', () {
      expect(
        DoctorVerificationRepository.parseVerifiedFromDoctorData({
          'mobile': '9999900002',
          'verified': false,
        }),
        isTrue,
      );
      expect(
        DoctorVerificationRepository.parseVerifiedFromDoctorData({
          'doctorId': '9999900002',
          'verified': false,
        }),
        isTrue,
      );
      expect(
        DoctorVerificationRepository.parseVerifiedFromDoctorData({
          'doctorId': 'd_9999900002',
          'verified': false,
        }),
        isTrue,
      );

      // Arbitrary non-reviewer accounts are NOT auto-verified
      expect(
        DoctorVerificationRepository.parseVerifiedFromDoctorData({
          'mobile': '9876543210',
          'verified': false,
        }),
        isFalse,
      );
    });

    test('Super Admin demo account is gated behind enableDemoSuperAdmin', () {
      if (!DemoAuthConfig.enableDemoSuperAdmin) {
        expect(DemoAuthConfig.isDemoSuperAdminPhone('9999988888'), isFalse);
      }
    });

    test('loose substring checks are strictly rejected (injection protection)', () {
      // Attacker doctorId containing demoDoctorPhone as substring must NOT match
      expect(DemoAuthConfig.isDemoDoctorId('hacker_9999900002_attack'), isFalse);
      expect(DemoAuthConfig.isDemoPharmacyId('store_9999900003_extra'), isFalse);
      expect(DemoAuthConfig.isDemoLabId('lab_9999900004_extra'), isFalse);
      expect(DemoAuthConfig.isDemoAmbulanceId('amb_9999900005_extra'), isFalse);

      // Non-demo numbers are not matched
      expect(DemoAuthConfig.isDemoDoctorPhone('9876543210'), isFalse);
    });
  });
}
