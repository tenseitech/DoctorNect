import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/enums/user_type.dart';
import 'package:medibond/core/firebase/firebase_bootstrap.dart';
import 'package:medibond/core/firebase/repositories/doctor_account_repository.dart';
import 'package:medibond/core/firebase/repositories/role_account_repository.dart';
import 'package:medibond/core/supabase/supabase_bootstrap.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakePostgrestFilterBuilder<T> extends Fake implements PostgrestFilterBuilder<T> {
  @override
  Future<R> then<R>(FutureOr<R> Function(T value) onValue, {Function? onError}) {
    return Future<T>.value(null as T).then(onValue, onError: onError);
  }

  @override
  Future<T> catchError(Function onError, {bool Function(Object error)? test}) {
    return Future<T>.value(null as T).catchError(onError, test: test);
  }

  @override
  Future<T> whenComplete(FutureOr<void> Function() action) {
    return Future<T>.value(null as T).whenComplete(action);
  }

  @override
  Stream<T> asStream() {
    return Stream<T>.value(null as T);
  }

  @override
  Future<T> timeout(Duration timeLimit, {FutureOr<T> Function()? onTimeout}) {
    return Future<T>.value(null as T).timeout(timeLimit, onTimeout: onTimeout);
  }
}

class FakeSupabaseClient extends Fake implements SupabaseClient {
  final List<String> invokedRpcs = [];

  @override
  PostgrestFilterBuilder<T> rpc<T>(
    String fn, {
    Map? params,
    dynamic body,
    dynamic get,
  }) {
    invokedRpcs.add(fn);
    return FakePostgrestFilterBuilder<T>();
  }
}

void main() {
  setUp(() {
    FirebaseBootstrap.isReady = false;
    SupabaseBootstrap.resetForTesting();
  });

  tearDown(() {
    FirebaseBootstrap.isReady = false;
    SupabaseBootstrap.resetForTesting();
  });

  group('Provider Lifecycle & Deactivation Status Tests', () {
    test('DoctorDeactivationStatus model stores state correctly', () {
      final now = DateTime.now();
      final status = DoctorDeactivationStatus(
        deactivated: true,
        canReactivate: true,
        reactivateBefore: now.add(const Duration(days: 30)),
      );

      expect(status.deactivated, isTrue);
      expect(status.canReactivate, isTrue);
      expect(status.reactivateBefore, isNotNull);
      expect(status.reactivateBefore!.isAfter(now), isTrue);
    });

    test('DoctorAccountRepository fetchDeactivationStatus returns inactive default when offline', () async {
      final status = await DoctorAccountRepository.instance.fetchDeactivationStatus('doc_123');
      expect(status.deactivated, isFalse);
      expect(status.canReactivate, isFalse);
      expect(status.reactivateBefore, isNull);
    });

    test('DoctorAccountRepository throws StateError if neither Firebase nor Supabase is ready', () async {
      expect(
        () => DoctorAccountRepository.instance.deactivate(
          doctorId: 'doc_123',
          ownerUid: 'uid_123',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('DoctorAccountRepository.deactivate invokes deactivate_provider_profile RPC via Supabase client', () async {
      final fakeClient = FakeSupabaseClient();
      SupabaseBootstrap.debugClientOverride = fakeClient;
      SupabaseBootstrap.isReady = true;

      await DoctorAccountRepository.instance.deactivate(
        doctorId: 'doc_123',
        ownerUid: 'uid_123',
      );

      expect(fakeClient.invokedRpcs, contains('deactivate_provider_profile'));
    });

    test('RoleAccountRepository invokes deactivate_provider_profile and reactivate_provider_profile RPCs', () async {
      final fakeClient = FakeSupabaseClient();
      SupabaseBootstrap.debugClientOverride = fakeClient;
      SupabaseBootstrap.isReady = true;

      // 1. Test lab provider deactivation and reactivation
      await RoleAccountRepository.instance.deactivateProvider(
        role: UserType.lab,
        profileId: 'lab_123',
        ownerUid: 'uid_lab',
      );
      expect(fakeClient.invokedRpcs, contains('deactivate_provider_profile'));

      await RoleAccountRepository.instance.reactivateProvider(
        role: UserType.lab,
        profileId: 'lab_123',
        ownerUid: 'uid_lab',
      );
      expect(fakeClient.invokedRpcs, contains('reactivate_provider_profile'));

      // 2. Test ambulance provider lifecycle
      fakeClient.invokedRpcs.clear();
      await RoleAccountRepository.instance.deactivateProvider(
        role: UserType.ambulance,
        profileId: 'amb_123',
        ownerUid: 'uid_amb',
      );
      expect(fakeClient.invokedRpcs, contains('deactivate_provider_profile'));

      await RoleAccountRepository.instance.reactivateProvider(
        role: UserType.ambulance,
        profileId: 'amb_123',
        ownerUid: 'uid_amb',
      );
      expect(fakeClient.invokedRpcs, contains('reactivate_provider_profile'));

      // 3. Test medical store provider lifecycle
      fakeClient.invokedRpcs.clear();
      await RoleAccountRepository.instance.deactivateProvider(
        role: UserType.medicalStore,
        profileId: 'store_123',
        ownerUid: 'uid_store',
      );
      expect(fakeClient.invokedRpcs, contains('deactivate_provider_profile'));

      await RoleAccountRepository.instance.reactivateProvider(
        role: UserType.medicalStore,
        profileId: 'store_123',
        ownerUid: 'uid_store',
      );
      expect(fakeClient.invokedRpcs, contains('reactivate_provider_profile'));
    });

    test('RoleAccountRepository role verification gates', () async {
      expect(await RoleAccountRepository.instance.isVerified(UserType.patient, 'p_1'), isTrue);
      expect(await RoleAccountRepository.instance.isVerified(UserType.lab, 'l_1'), isTrue);
      expect(await RoleAccountRepository.instance.isVerified(UserType.medicalStore, 'm_1'), isTrue);
      expect(await RoleAccountRepository.instance.isVerified(UserType.ambulance, 'a_1'), isTrue);
    });
  });
}
