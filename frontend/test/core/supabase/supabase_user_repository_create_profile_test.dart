import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/enums/user_type.dart';
import 'package:medibond/core/supabase/profile_creation_exception.dart';
import 'package:medibond/core/supabase/repositories/supabase_user_repository.dart';
import 'package:medibond/core/supabase/supabase_bootstrap.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

class MockUser extends Mock implements User {}

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockSupabaseQueryBuilder extends Mock implements SupabaseQueryBuilder {}

void main() {
  late MockSupabaseClient mockClient;
  late MockSupabaseQueryBuilder usersBuilder;
  late MockUser mockUser;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    SupabaseBootstrap.resetForTesting();
    mockClient = MockSupabaseClient();
    usersBuilder = MockSupabaseQueryBuilder();
    mockUser = MockUser();

    when(() => mockUser.uid).thenReturn('uid_create_test');
    when(() => mockUser.email).thenReturn('patient@test.com');
    when(() => mockClient.from('users')).thenAnswer((_) => usersBuilder);

    SupabaseBootstrap.debugClientOverride = mockClient;
    SupabaseBootstrap.isReady = true;
    SupabaseUserRepository.createProfileMaxAttempts = 3;
    SupabaseUserRepository.debugCreateProfileRetryDelay = (_) => Duration.zero;
  });

  tearDown(() {
    SupabaseBootstrap.resetForTesting();
    SupabaseUserRepository.createProfileMaxAttempts = 3;
    SupabaseUserRepository.debugCreateProfileRetryDelay = null;
  });

  group('SupabaseUserRepository.createProfile', () {
    test('retries transient 503 then succeeds (retry helper on real repository)',
        () async {
      var attempts = 0;
      await SupabaseUserRepository.instance.runProfileWriteRetryForTesting(
        () async {
          attempts++;
          if (attempts < 3) {
            throw PostgrestException(
              message: 'Service Unavailable',
              code: '503',
              details: '',
              hint: '',
            );
          }
        },
      );

      expect(attempts, 3);
    });

    test('throws ProfileCreationException after retry budget exhausted', () async {
      when(
        () => usersBuilder.upsert(
          any(),
          onConflict: any(named: 'onConflict'),
        ),
      ).thenThrow(
        PostgrestException(
          message: '503 Service Unavailable',
          code: '503',
          details: '',
          hint: '',
        ),
      );

      await expectLater(
        SupabaseUserRepository.instance.createProfile(
          user: mockUser,
          role: UserType.patient,
          profileId: 'patient_2',
          displayName: 'Test Patient',
          mobile: '9876543210',
        ),
        throwsA(isA<ProfileCreationException>()),
      );
    });

    test('isRetryableProfileWriteError recognizes 503 PostgrestException', () {
      expect(
        SupabaseUserRepository.isRetryableProfileWriteError(
          PostgrestException(
            message: 'down',
            code: '503',
            details: '',
            hint: '',
          ),
        ),
        isTrue,
      );
    });
  });
}
