import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:medibond/core/auth/registration_otp_service.dart';
import 'package:medibond/core/enums/user_type.dart';
import 'package:medibond/core/firebase/firebase_auth_service.dart';
import 'package:medibond/core/firebase/firebase_bootstrap.dart';
import 'package:medibond/core/firebase/models/medibond_user_profile.dart';
import 'package:medibond/core/firebase/repositories/user_repository.dart';
import 'package:medibond/core/supabase/repositories/supabase_user_repository.dart';
import 'package:medibond/core/validation/server_validation_service.dart';

import 'helpers/auth_validation_rules_fixture.dart';

class MockUser extends Mock implements User {}

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUserCredential extends Mock implements UserCredential {}

class MockSupabaseUserRepository extends Mock implements SupabaseUserRepository {}

class FakeUser extends Fake implements User {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeUser());
    registerFallbackValue(UserType.patient);
  });

  setUp(() {
    ServerValidationService.debugSetRules(authValidationRulesFixture());
    FirebaseBootstrap.isReady = true;
  });

  tearDown(() {
    ServerValidationService.debugReset();
    FirebaseBootstrap.isReady = false;
    FirebaseAuthService.debugAuth = null;
    UserRepository.debugSupabaseUserRepository = null;
    RegistrationOtpService.debugFinalizeRegistrationVerification = null;
    RegistrationOtpService.clearVerificationSession();
    RegistrationOtpService.debugCleanupPendingRegistration = null;
    SupabaseUserRepository.debugDeleteFreshOrphanProfileRows = null;
    SupabaseUserRepository.debugIsRegistrationProfileAlreadyVerified = null;
  });

  group('SupabaseUserRepository.deletePendingAuthUser', () {
    test('calls Firebase User.delete for the registration attempt user', () async {
      final user = MockUser();
      when(() => user.uid).thenReturn('delete_pending_uid');
      when(() => user.delete()).thenAnswer((_) async {});

      await SupabaseUserRepository.instance.deletePendingAuthUser(user);

      verify(() => user.delete()).called(1);
    });

    test('skips auth delete when profile row is already verified', () async {
      final user = MockUser();
      when(() => user.uid).thenReturn('verified_skip_uid');
      SupabaseUserRepository.debugIsRegistrationProfileAlreadyVerified =
          (_) async => true;

      final outcome =
          await SupabaseUserRepository.instance.deletePendingAuthUser(user);

      expect(outcome, SupabaseUserRepository.pendingAuthSkippedAlreadyVerified);
      verifyNever(() => user.delete());
    });
  });

  group('FirebaseAuthService.registerProfile rollback', () {
    late MockUser mockUser;
    late MockFirebaseAuth mockAuth;
    late MockUserCredential mockCredential;
    late MockSupabaseUserRepository mockRepo;

    setUp(() {
      mockUser = MockUser();
      mockAuth = MockFirebaseAuth();
      mockCredential = MockUserCredential();
      mockRepo = MockSupabaseUserRepository();

      FirebaseAuthService.debugAuth = mockAuth;
      UserRepository.debugSupabaseUserRepository = mockRepo;

      when(() => mockUser.uid).thenReturn('reg_rollback_uid');
      when(() => mockUser.email).thenReturn('rollback@test.com');
      when(() => mockUser.delete()).thenAnswer((_) async {});
      when(() => mockUser.getIdToken(any())).thenAnswer((_) async => 'token');
      when(() => mockCredential.user).thenReturn(mockUser);
      when(() => mockAuth.createUserWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenAnswer((_) async => mockCredential);
      when(() => mockAuth.signOut()).thenAnswer((_) async {});
      when(() => mockRepo.validateNewRegistration(
            role: any(named: 'role'),
            email: any(named: 'email'),
            mobile: any(named: 'mobile'),
            profileId: any(named: 'profileId'),
            roleData: any(named: 'roleData'),
          )).thenAnswer((_) async => null);
      when(() => mockRepo.createProfile(
            user: any(named: 'user'),
            role: any(named: 'role'),
            profileId: any(named: 'profileId'),
            displayName: any(named: 'displayName'),
            mobile: any(named: 'mobile'),
            mobileVerified: any(named: 'mobileVerified'),
            roleData: any(named: 'roleData'),
          )).thenAnswer((_) async {});
      RegistrationOtpService.debugCleanupPendingRegistration =
          () async => (ok: true, cleaned: true);

      when(() => mockRepo.deletePendingAuthUser(any())).thenAnswer((invocation) async {
        final pendingUser = invocation.positionalArguments[0] as User;
        return SupabaseUserRepository.instance.deletePendingAuthUser(pendingUser);
      });
    });

    test('profile read timeout deletes pending auth user before sign-out', () async {
      when(() => mockRepo.fetchProfile(any(), preferCache: any(named: 'preferCache')))
          .thenAnswer((_) async => null);

      final result = await FirebaseAuthService.instance.registerProfile(
        role: UserType.patient,
        email: 'rollback@test.com',
        password: 'Password1!',
        profileId: 'patient_rb_1',
        displayName: 'Rollback Test',
      );

      expect(result.success, isFalse);
      verify(() => mockRepo.deletePendingAuthUser(mockUser)).called(1);
      verify(() => mockAuth.signOut()).called(1);
    });

    test('finalize OTP failure deletes pending auth user before sign-out', () async {
      when(() => mockRepo.fetchProfile(any(), preferCache: any(named: 'preferCache')))
          .thenAnswer(
        (_) async => DoctorNectUserProfile(
          uid: 'reg_rollback_uid',
          role: UserType.patient,
          profileId: 'patient_rb_2',
          displayName: 'Rollback Test',
          email: 'rollback@test.com',
        ),
      );
      RegistrationOtpService.debugFinalizeRegistrationVerification =
          (_) async => 'Finalize failed';

      final result = await FirebaseAuthService.instance.registerProfile(
        role: UserType.patient,
        email: 'rollback@test.com',
        password: 'Password1!',
        profileId: 'patient_rb_2',
        displayName: 'Rollback Test',
        mobile: '9876543210',
        otpVerificationSessionId: 'sess-finalize-fail',
      );

      expect(result.success, isFalse);
      verify(() => mockRepo.deletePendingAuthUser(mockUser)).called(1);
      verify(() => mockAuth.signOut()).called(1);
    });

    test('orphan profile row cleared so same mobile/email pass duplicate check on retry', () async {
      final orphanProfileRows = <String, Map<String, dynamic>>{};
      const mobile = '9876543210';
      const email = 'rollback@test.com';

      SupabaseUserRepository.debugDeleteFreshOrphanProfileRows = (uid) async {
        orphanProfileRows.remove(uid);
      };

      when(() => mockRepo.createProfile(
            user: any(named: 'user'),
            role: any(named: 'role'),
            profileId: any(named: 'profileId'),
            displayName: any(named: 'displayName'),
            mobile: any(named: 'mobile'),
            mobileVerified: any(named: 'mobileVerified'),
            roleData: any(named: 'roleData'),
          )).thenAnswer((invocation) async {
        final profileUser = invocation.namedArguments[#user] as User;
        orphanProfileRows[profileUser.uid] = {
          'email': email,
          'mobile': mobile,
          'created_at': DateTime.now().toIso8601String(),
          'mobile_verified': false,
          'email_verified': false,
        };
      });

      when(() => mockRepo.validateNewRegistration(
            role: any(named: 'role'),
            email: any(named: 'email'),
            mobile: any(named: 'mobile'),
            profileId: any(named: 'profileId'),
            roleData: any(named: 'roleData'),
          )).thenAnswer((_) async {
        if (orphanProfileRows.isNotEmpty) {
          return 'An account with this email or mobile already exists.';
        }
        return null;
      });

      when(() => mockRepo.fetchProfile(any(), preferCache: any(named: 'preferCache')))
          .thenAnswer(
        (_) async => DoctorNectUserProfile(
          uid: 'reg_rollback_uid',
          role: UserType.patient,
          profileId: 'patient_rb_retry',
          displayName: 'Rollback Test',
          email: email,
          mobile: mobile,
        ),
      );
      RegistrationOtpService.debugFinalizeRegistrationVerification =
          (_) async => 'Finalize failed';

      final first = await FirebaseAuthService.instance.registerProfile(
        role: UserType.patient,
        email: email,
        password: 'Password1!',
        profileId: 'patient_rb_retry',
        displayName: 'Rollback Test',
        mobile: mobile,
        otpVerificationSessionId: 'sess-retry-1',
      );
      expect(first.success, isFalse);
      expect(orphanProfileRows, isEmpty);

      final retryValidation = await mockRepo.validateNewRegistration(
        role: UserType.patient,
        email: email,
        mobile: mobile,
        profileId: 'patient_rb_retry_2',
      );
      expect(retryValidation, isNull);
      verify(() => mockUser.delete()).called(1);
    });

    test('calls cleanup callable before sign-out on finalize failure', () async {
      var cleanupCalled = false;
      RegistrationOtpService.debugCleanupPendingRegistration = () async {
        cleanupCalled = true;
        return (ok: true, cleaned: true);
      };

      when(() => mockRepo.fetchProfile(any(), preferCache: any(named: 'preferCache')))
          .thenAnswer(
        (_) async => DoctorNectUserProfile(
          uid: 'reg_rollback_uid',
          role: UserType.patient,
          profileId: 'patient_rb_callable',
          displayName: 'Rollback Test',
          email: 'rollback@test.com',
          mobile: '9876543210',
        ),
      );
      RegistrationOtpService.debugFinalizeRegistrationVerification =
          (_) async => 'Finalize failed';

      final result = await FirebaseAuthService.instance.registerProfile(
        role: UserType.patient,
        email: 'rollback@test.com',
        password: 'Password1!',
        profileId: 'patient_rb_callable',
        displayName: 'Rollback Test',
        mobile: '9876543210',
        otpVerificationSessionId: 'sess-callable-first',
      );

      expect(result.success, isFalse);
      expect(cleanupCalled, isTrue);
      verify(() => mockAuth.signOut()).called(1);
    });

    test('finalize response lost keeps auth when profile already verified on server',
        () async {
      when(() => mockRepo.deletePendingAuthUser(any())).thenAnswer(
        (_) async => SupabaseUserRepository.pendingAuthSkippedAlreadyVerified,
      );

      when(() => mockRepo.fetchProfile(any(), preferCache: any(named: 'preferCache')))
          .thenAnswer(
        (_) async => DoctorNectUserProfile(
          uid: 'reg_rollback_uid',
          role: UserType.patient,
          profileId: 'patient_rb_verified',
          displayName: 'Rollback Test',
          email: 'rollback@test.com',
          mobile: '9876543210',
        ),
      );
      RegistrationOtpService.debugFinalizeRegistrationVerification =
          (_) async => 'Network timeout';

      await FirebaseAuthService.instance.registerProfile(
        role: UserType.patient,
        email: 'rollback@test.com',
        password: 'Password1!',
        profileId: 'patient_rb_verified',
        displayName: 'Rollback Test',
        mobile: '9876543210',
        otpVerificationSessionId: 'sess-response-lost',
      );

      verify(() => mockRepo.deletePendingAuthUser(mockUser)).called(1);
      verifyNever(() => mockUser.delete());
      verifyNever(() => mockAuth.signOut());
    });
  });
}
