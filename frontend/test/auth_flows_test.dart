import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:mocktail/mocktail.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:medibond/core/firebase/repositories/user_repository.dart';
import 'package:medibond/core/supabase/repositories/supabase_user_repository.dart';
import 'package:medibond/core/supabase/supabase_bootstrap.dart';
import 'package:medibond/core/config/doctor_patient_cutover_flag.dart';

import 'package:medibond/core/auth/last_login_store.dart';
import 'package:medibond/core/auth/registration_otp_service.dart';
import 'package:medibond/core/enums/user_type.dart';
import 'package:medibond/core/firebase/firebase_auth_service.dart';
import 'package:medibond/core/firebase/firebase_bootstrap.dart';
import 'package:medibond/core/validation/server_validation_service.dart';
import 'package:medibond/core/validators/form_validators.dart';

import 'helpers/auth_validation_rules_fixture.dart';

class MockUser extends Mock implements User {}
class MockFirebaseAuth extends Mock implements FirebaseAuth {}
class MockSupabaseUserRepository extends Mock implements SupabaseUserRepository {}
class FakeUser extends Fake implements User {}


void main() {
  setUpAll(() {
    registerFallbackValue(FakeUser());
    registerFallbackValue(UserType.patient);
  });
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
      expect(
        FormValidators.registrationMobileDigits('9876543210'),
        '9876543210',
      );
      expect(
        FormValidators.registrationMobileDigits('+919876543210'),
        '9876543210',
      );
      expect(
        FormValidators.registrationMobileDigits('09876543210'),
        '9876543210',
      );
      expect(
        FormValidators.registrationMobileDigits('919876543210'),
        '9876543210',
      );
    });

    test('registrationMobileDigits rejects wrong length or invalid prefix', () {
      expect(FormValidators.registrationMobileDigits('12345'), isNull);
      expect(FormValidators.registrationMobileDigits('5876543210'), isNull);
    });

    test('phoneLocal rejects invalid Indian prefix', () {
      expect(
        FormValidators.phoneLocal('5876543210', dialCode: '+91'),
        isNotNull,
      );
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
      expect(
        FormValidators.phoneLocal('1234567890', dialCode: '+91'),
        isNotNull,
      );
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

  group('RegistrationOtpService — cloud OTP flow', () {
    test('requires Firebase before calling Cloud Functions', () async {
      FirebaseBootstrap.isReady = false;
      RegistrationOtpService.clearPending(validMobile);

      final send = await RegistrationOtpService.sendOtp(validMobile);
      expect(send.error, 'Firebase is not available.');

      final verify = await RegistrationOtpService.verify(validMobile, '123456');
      expect(verify, 'Firebase is not available.');
    });

    test('clearPending clears cached verification session', () {
      RegistrationOtpService.clearPending(validMobile);
      expect(RegistrationOtpService.verificationSessionId, isNull);
    });

    test('isLocalVerificationSession is always false', () {
      expect(
        RegistrationOtpService.isLocalVerificationSession('local:9876543210'),
        isFalse,
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

  group('FirebaseAuthService — registration null-profile resilience', () {
    test('profile timeout result preserves account without premature deletion message', () {
      final timeoutResult = AuthSignInResult.fail(
        'Account created, but profile verification timed out. Please sign in to continue.',
      );
      expect(timeoutResult.success, isFalse);
      expect(timeoutResult.message, contains('profile verification timed out'));
      expect(timeoutResult.message, contains('Please sign in to continue'));
      expect(timeoutResult.message, isNot(contains('delete')));
    });

    test('network issue result during profile save preserves user account without deletion', () {
      final networkErrorResult = AuthSignInResult.fail(
        'Registration encountered a network issue while saving profile. Please check your connection and try again.',
      );
      expect(networkErrorResult.success, isFalse);
      expect(networkErrorResult.message, contains('saving profile'));
      expect(networkErrorResult.message, contains('check your connection'));
      expect(networkErrorResult.message, isNot(contains('delete')));
    });


  });

  group('Real UserRepository & FirebaseAuthService Resilience (Fakes & Mocks)', () {
    late FakeFirebaseFirestore fakeDb;
    late MockUser mockUser;
    late MockFirebaseAuth mockAuth;
    late MockSupabaseUserRepository mockSupabaseRepo;

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      UserRepository.debugFirestore = fakeDb;

      mockUser = MockUser();
      mockAuth = MockFirebaseAuth();
      mockSupabaseRepo = MockSupabaseUserRepository();

      FirebaseAuthService.debugAuth = mockAuth;
      UserRepository.debugSupabaseUserRepository = mockSupabaseRepo;
    });

    tearDown(() {
      UserRepository.debugFirestore = null;
      UserRepository.debugSupabaseUserRepository = null;
      FirebaseAuthService.debugAuth = null;
      DoctorPatientCutoverFlag.debugOverride = null;
      SupabaseBootstrap.isReady = false;
    });

    test('(a) profile null after 3 attempts triggers signOut and does NOT call user.delete()', () async {
      when(() => mockUser.uid).thenReturn('orphan_user_123');
      when(() => mockAuth.signOut()).thenAnswer((_) async {});

      final profile = await FirebaseAuthService.instance.verifyProfileWithRetry(
        user: mockUser,
        maxAttempts: 3,
        delayFn: (_) => Duration.zero,
      );

      expect(profile, isNull);
      verify(() => mockAuth.signOut()).called(1);
      verifyNever(() => mockUser.delete());
    });

    test('(b) SupabaseUserRepository.createProfile exception is non-fatal and Firestore write succeeds', () async {
      when(() => mockUser.uid).thenReturn('dual_write_uid_456');
      when(() => mockUser.email).thenReturn('patient@test.com');

      when(() => mockSupabaseRepo.createProfile(
        user: any(named: 'user'),
        role: any(named: 'role'),
        profileId: any(named: 'profileId'),
        displayName: any(named: 'displayName'),
        mobile: any(named: 'mobile'),
        mobileVerified: any(named: 'mobileVerified'),
        roleData: any(named: 'roleData'),
      )).thenThrow(Exception('Supabase network error: 503 Service Unavailable'));

      SupabaseBootstrap.isReady = true;
      DoctorPatientCutoverFlag.debugOverride = true;

      await UserRepository.instance.createProfile(
        user: mockUser,
        role: UserType.patient,
        profileId: 'patient_profile_789',
        displayName: 'Test Patient',
        mobile: '9876543210',
        mobileVerified: true,
      );

      final userDoc = await fakeDb.collection('users').doc('dual_write_uid_456').get();
      expect(userDoc.exists, isTrue);
      expect(userDoc.data()?['role'], 'patient');
      expect(userDoc.data()?['profileId'], 'patient_profile_789');
      expect(userDoc.data()?['displayName'], 'Test Patient');
      expect(userDoc.data()?['email'], 'patient@test.com');
      expect(userDoc.data()?['mobile'], '9876543210');

      final claimDoc = await fakeDb.collection('profile_claims').doc('patient_profile_789').get();
      expect(claimDoc.exists, isTrue);
      expect(claimDoc.data()?['uid'], 'dual_write_uid_456');
    });

    test('(c) orphan Firebase Auth user with role doc repairs users/{uid} and completes login', () async {
      when(() => mockUser.uid).thenReturn('orphan_repaired_uid');
      when(() => mockUser.email).thenReturn('orphan@example.com');

      await fakeDb.collection('patients').doc('patient_rep_001').set({
        'patientId': 'patient_rep_001',
        'ownerUid': 'orphan_repaired_uid',
        'name': 'Repaired Patient',
        'email': 'orphan@example.com',
        'mobile': '9876543210',
        'profileCompleted': true,
      });

      final initialUserDoc = await fakeDb.collection('users').doc('orphan_repaired_uid').get();
      expect(initialUserDoc.exists, isFalse);

      final repaired = await UserRepository.instance.repairMissingProfile(
        user: mockUser,
        expectedRole: UserType.patient,
      );

      expect(repaired, isNotNull);
      expect(repaired!.role, UserType.patient);
      expect(repaired.displayName, 'Repaired Patient');

      final repairedUserDoc = await fakeDb.collection('users').doc('orphan_repaired_uid').get();
      expect(repairedUserDoc.exists, isTrue);
      expect(repairedUserDoc.data()?['profileId'], 'patient_rep_001');
      expect(repairedUserDoc.data()?['role'], 'patient');
    });

    test('(d) orphan Firebase Auth user with NO role doc returns null cleanly without hanging', () async {
      when(() => mockUser.uid).thenReturn('unrepairable_orphan_uid');
      when(() => mockUser.email).thenReturn('unrepairable@example.com');

      final repaired = await UserRepository.instance.repairMissingProfile(
        user: mockUser,
        expectedRole: UserType.patient,
      );

      expect(repaired, isNull);
    });


    test('(i) role doc ka ownerUid kisi aur uid ka ho, repair null return kare aur users/{uid} na bane', () async {
      when(() => mockUser.uid).thenReturn('attacker_uid_111');
      when(() => mockUser.email).thenReturn('attacker@example.com');

      // Patient doc belongs to victim_uid_999
      await fakeDb.collection('patients').doc('patient_victim_001').set({
        'patientId': 'patient_victim_001',
        'ownerUid': 'victim_uid_999',
        'name': 'Victim Patient',
        'email': 'victim@example.com',
        'mobile': '9111111111',
        'profileCompleted': true,
      });

      final repaired = await UserRepository.instance.repairMissingProfile(
        user: mockUser,
        expectedRole: UserType.patient,
      );

      expect(repaired, isNull);
      final attackerUserDoc = await fakeDb.collection('users').doc('attacker_uid_111').get();
      expect(attackerUserDoc.exists, isFalse);
    });

    test('(ii) user ka role doc patients mein ho par expectedRole doctor ho, null return kare aur users/{uid} na bane', () async {
      when(() => mockUser.uid).thenReturn('cross_role_uid_222');
      when(() => mockUser.email).thenReturn('cross@example.com');

      // User has a legitimate patient doc
      await fakeDb.collection('patients').doc('patient_cross_002').set({
        'patientId': 'patient_cross_002',
        'ownerUid': 'cross_role_uid_222',
        'name': 'Cross Role User',
        'email': 'cross@example.com',
        'mobile': '9222222222',
        'profileCompleted': true,
      });

      // Attacker asks to repair as doctor
      final repaired = await UserRepository.instance.repairMissingProfile(
        user: mockUser,
        expectedRole: UserType.doctor,
      );

      expect(repaired, isNull);
      final userDoc = await fakeDb.collection('users').doc('cross_role_uid_222').get();
      expect(userDoc.exists, isFalse);
    });
  });
}
