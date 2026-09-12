import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/auth/last_login_store.dart';
import 'package:medibond/core/auth/registration_otp_service.dart';
import 'package:medibond/core/enums/user_type.dart';
import 'package:medibond/core/firebase/firebase_auth_service.dart';
import 'package:medibond/core/firebase/firebase_bootstrap.dart';
import 'package:medibond/core/validation/server_validation_service.dart';
import 'package:medibond/core/validators/form_validators.dart';

import 'helpers/auth_validation_rules_fixture.dart';

void main() {
  const validMobile = '9876543210';
  const validEmail = 'patient@example.com';

  setUp(() {
    ServerValidationService.debugSetRules(authValidationRulesFixture());
  });

  tearDown(() {
    ServerValidationService.debugReset();
    FirebaseBootstrap.isReady = false;
    RegistrationOtpService.clearPending(validMobile);
    RegistrationOtpService.clearVerificationSession();
    LastLoginStore.clear(UserType.patient);
    LastLoginStore.clear(UserType.doctor);
  });

  group('AuthSignInResult', () {
    test('ok marks success with role', () {
      final result = AuthSignInResult.ok(UserType.patient);
      expect(result.success, isTrue);
      expect(result.role, UserType.patient);
      expect(result.needsRegistration, isFalse);
      expect(result.pendingReview, isFalse);
    });

    test('fail carries message', () {
      final result = AuthSignInResult.fail('Invalid credentials');
      expect(result.success, isFalse);
      expect(result.message, 'Invalid credentials');
    });

    test('needsRegistration flag', () {
      final result = AuthSignInResult.needsRegistration();
      expect(result.success, isFalse);
      expect(result.needsRegistration, isTrue);
    });

    test('pendingReview flag', () {
      final result = AuthSignInResult.pendingReview();
      expect(result.success, isFalse);
      expect(result.pendingReview, isTrue);
    });

    test('deactivatedCanReactivate carries reactivation window', () {
      final deadline = DateTime(2026, 8, 1);
      final result = AuthSignInResult.deactivatedCanReactivate(
        reactivateBefore: deadline,
      );
      expect(result.canReactivateAccount, isTrue);
      expect(result.reactivateBefore, deadline);
    });
  });

  group('FormValidators — registration inputs', () {
    test('email accepts valid address', () {
      expect(FormValidators.email(validEmail), isNull);
    });

    test('email rejects invalid address', () {
      expect(FormValidators.email('not-an-email'), isNotNull);
    });

    test('optionalEmail allows empty', () {
      expect(FormValidators.optionalEmail(''), isNull);
      expect(FormValidators.optionalEmail(null), isNull);
    });

    test('registrationMobileDigits normalizes Indian formats', () {
      expect(FormValidators.registrationMobileDigits('9876543210'), '9876543210');
      expect(FormValidators.registrationMobileDigits('+919876543210'), '9876543210');
      expect(FormValidators.registrationMobileDigits('09876543210'), '9876543210');
      expect(FormValidators.registrationMobileDigits('919876543210'), '9876543210');
    });

    test('registrationMobileDigits rejects wrong length only', () {
      expect(FormValidators.registrationMobileDigits('12345'), isNull);
      expect(FormValidators.registrationMobileDigits('5876543210'), '5876543210');
    });

    test('phoneLocal rejects invalid Indian prefix', () {
      expect(FormValidators.phoneLocal('5876543210', dialCode: '+91'), isNotNull);
    });

    test('parsePhone handles E.164 and local formats', () {
      final e164 = FormValidators.parsePhone('+919876543210');
      expect(e164.dialCode, '+91');
      expect(e164.localNumber, '9876543210');

      final local = FormValidators.parsePhone('9876543210');
      expect(local.dialCode, '+91');
      expect(local.localNumber, '9876543210');
    });

    test('phoneLocal validates 10-digit Indian mobile', () {
      expect(FormValidators.phoneLocal(validMobile, dialCode: '+91'), isNull);
      expect(FormValidators.phoneLocal('1234567890', dialCode: '+91'), isNotNull);
    });

    test('otp requires exactly six digits', () {
      expect(FormValidators.otp('123456'), isNull);
      expect(FormValidators.otp('12345'), isNotNull);
      expect(FormValidators.otp('abcdef'), isNotNull);
    });

    test('confirmPassword must match', () {
      expect(FormValidators.confirmPassword('secret', 'secret'), isNull);
      expect(FormValidators.confirmPassword('other', 'secret'), isNotNull);
    });
  });

  group('LastLoginStore', () {
    test('save, load, and clear per role', () async {
      expect(LastLoginStore.readCached(UserType.patient), isNull);

      await LastLoginStore.save(UserType.patient, '  $validEmail  ');
      expect(LastLoginStore.readCached(UserType.patient), validEmail);
      expect(await LastLoginStore.load(UserType.patient), validEmail);

      await LastLoginStore.clear(UserType.patient);
      expect(LastLoginStore.readCached(UserType.patient), isNull);
    });

    test('save ignores blank email', () async {
      await LastLoginStore.save(UserType.doctor, '   ');
      expect(LastLoginStore.readCached(UserType.doctor), isNull);
    });

    test('roles are isolated', () async {
      await LastLoginStore.save(UserType.patient, 'a@test.com');
      await LastLoginStore.save(UserType.doctor, 'b@test.com');
      expect(LastLoginStore.readCached(UserType.patient), 'a@test.com');
      expect(LastLoginStore.readCached(UserType.doctor), 'b@test.com');
    });
  });

  group('RegistrationOtpService — input validation', () {
    test('sendOtp rejects invalid mobile before Firebase', () async {
      final result = await RegistrationOtpService.sendOtp('12345');
      expect(result.error, isNotNull);
      expect(result.debugOtp, isNull);
    });

    test('verify rejects malformed OTP', () async {
      final error = await RegistrationOtpService.verify(validMobile, 'abc');
      expect(error, isNotNull);
    });

    test('verify rejects invalid mobile digits', () async {
      final error = await RegistrationOtpService.verify('12345', '123456');
      expect(error, isNotNull);
    });

    test('requires Firebase when no local pending session', () async {
      FirebaseBootstrap.isReady = false;
      final send = await RegistrationOtpService.sendOtp(validMobile);
      expect(send.error, 'Firebase is not available.');

      final verify = await RegistrationOtpService.verify(validMobile, '123456');
      expect(verify, 'Firebase is not available.');
    });
  });

  group('RegistrationOtpService — local debug OTP flow', () {
    test('send, verify, and finalize local session', () async {
      expect(kDebugMode, isTrue, reason: 'Local OTP fallback is debug-only');

      FirebaseBootstrap.isReady = true;
      RegistrationOtpService.clearPending(validMobile);

      final send = await RegistrationOtpService.sendOtp(validMobile);
      expect(send.error, isNull);
      expect(send.debugOtp, '123456');

      final badOtp = await RegistrationOtpService.verify(validMobile, '000000');
      expect(badOtp, 'Invalid OTP.');

      final ok = await RegistrationOtpService.verify(validMobile, '123456');
      expect(ok, isNull);

      final sessionId = RegistrationOtpService.verificationSessionId;
      expect(sessionId, isNotNull);
      expect(
        RegistrationOtpService.isLocalVerificationSession(sessionId),
        isTrue,
      );

      final finalize =
          await RegistrationOtpService.finalizePatientVerification(sessionId!);
      expect(finalize, isNull);
      expect(RegistrationOtpService.verificationSessionId, isNull);
    });

    test('verify without prior send is blocked', () async {
      FirebaseBootstrap.isReady = false;
      RegistrationOtpService.clearPending(validMobile);

      final error = await RegistrationOtpService.verify(validMobile, '123456');
      expect(error, 'Firebase is not available.');
    });

    test('clearPending removes local session state', () async {
      FirebaseBootstrap.isReady = true;

      await RegistrationOtpService.sendOtp(validMobile);
      await RegistrationOtpService.verify(validMobile, '123456');
      expect(RegistrationOtpService.verificationSessionId, isNotNull);

      RegistrationOtpService.clearPending(validMobile);
      expect(RegistrationOtpService.verificationSessionId, isNull);
    });

    test('isLocalVerificationSession is false outside debug', () {
      expect(
        RegistrationOtpService.isLocalVerificationSession('local:9876543210'),
        kDebugMode,
      );
    });
  });

  group('FirebaseAuthService — login guard', () {
    test('signInWithEmail fails when Firebase is unavailable', () async {
      FirebaseBootstrap.isReady = false;

      final result = await FirebaseAuthService.instance.signInWithEmail(
        expectedRole: UserType.patient,
        email: validEmail,
        password: 'password123',
      );

      expect(result.success, isFalse);
      expect(result.message, contains('Firebase is not available'));
    });
  });
}
