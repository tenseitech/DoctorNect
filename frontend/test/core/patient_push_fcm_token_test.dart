import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/config/firestore_forbidden_guard.dart';
import 'package:medibond/core/firebase/repositories/patient_profile_repository.dart';
import 'package:medibond/core/notifications/patient_push_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    FirestoreForbiddenGuard.resetForTesting();
  });

  test('FCM token persist failure does not throw (release guard on)', () async {
    FirestoreForbiddenGuard.debugForceReleaseMode = true;
    expect(
      () => FirestoreForbiddenGuard.isForbidden,
      returnsNormally,
    );
    await expectLater(
      PatientPushService.persistTokenForTest('pat-test-1', 'token-abc'),
      completes,
    );
    await expectLater(
      PatientProfileRepository.instance.savePatientFcmToken(
        'pat-test-1',
        'token-abc',
      ),
      completes,
    );
  });
}
