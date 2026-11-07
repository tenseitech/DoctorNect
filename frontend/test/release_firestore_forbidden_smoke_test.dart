import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/config/firestore_forbidden_guard.dart';
import 'package:medibond/core/config/ambulance_enabled.dart';
import 'package:medibond/core/firebase/firestore_service.dart';
import 'package:medibond/core/firebase/firestore_ui.dart';

void main() {
  tearDown(() {
    FirestoreForbiddenGuard.resetForTesting();
    FirestoreForbiddenGuard.debugOverrideForTesting = false;
    AmbulanceEnabled.resetForTesting();
  });

  group('release Firestore forbidden smoke', () {
    test('FirestoreService throws under debugForceReleaseMode', () {
      FirestoreForbiddenGuard.resetForTesting();
      FirestoreForbiddenGuard.debugForceReleaseMode = true;
      expect(() => FirestoreService.instance, throwsStateError);
    });

    test('FirestoreUi.guardSync returns null instead of throwing', () {
      FirestoreForbiddenGuard.resetForTesting();
      FirestoreForbiddenGuard.debugForceReleaseMode = true;
      String? shown;
      final v = FirestoreUi.guardSync(
        () => FirestoreService.instance,
        showError: (m) => shown = m,
      );
      expect(v, isNull);
      expect(shown, FirestoreUi.userMessage);
    });

    test('ambulance deep routes off by default in release', () {
      AmbulanceEnabled.debugOverride = false;
      expect(AmbulanceEnabled.isOn, isFalse);
    });
  });
}
