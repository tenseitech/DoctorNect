import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/enums/user_type.dart';
import 'package:medibond/core/firebase/firebase_bootstrap.dart';
import 'package:medibond/core/firebase/repositories/doctor_account_repository.dart';
import 'package:medibond/core/firebase/repositories/role_account_repository.dart';
import 'package:medibond/core/supabase/supabase_bootstrap.dart';

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

      expect(
        () => DoctorAccountRepository.instance.reactivate(
          doctorId: 'doc_123',
          ownerUid: 'uid_123',
        ),
        returnsNormally, // fetchDeactivationStatus returns deactivated=false so early returns
      );
    });

    test('RoleAccountRepository role verification gates', () async {
      expect(await RoleAccountRepository.instance.isVerified(UserType.patient, 'p_1'), isTrue);
      expect(await RoleAccountRepository.instance.isVerified(UserType.lab, 'l_1'), isTrue);
      expect(await RoleAccountRepository.instance.isVerified(UserType.medicalStore, 'm_1'), isTrue);
      expect(await RoleAccountRepository.instance.isVerified(UserType.ambulance, 'a_1'), isTrue);
    });
  });
}
