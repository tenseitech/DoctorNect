import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/config/firestore_forbidden_guard.dart';
import 'package:medibond/core/firebase/firebase_bootstrap.dart';
import 'package:medibond/core/config/ambulance_enabled.dart';
import 'package:medibond/core/firebase/firestore_service.dart';
import 'package:medibond/core/firebase/firestore_ui.dart';
import 'package:medibond/features/doctor/verification/doctor_verification_gate.dart';
import 'package:medibond/features/doctor/verification/doctor_verification_pending_screen.dart';
import 'package:medibond/features/patient/home/patient_home_screen.dart';
import 'package:medibond/features/patient/profile/data/patient_profile_mock.dart';
import 'package:medibond/features/patient/profile/models/patient_profile_models.dart';
import 'package:medibond/features/patient/search/doctor_search_screen.dart';
import 'package:medibond/features/welcome/welcome_screen.dart';

void main() {
  tearDown(() {
    FirestoreForbiddenGuard.resetForTesting();
    AmbulanceEnabled.resetForTesting();
    PatientProfileMock.reset();
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

  group('launch-critical entry screens (release guard)', () {
    setUp(() {
      FirestoreForbiddenGuard.resetForTesting();
      FirestoreForbiddenGuard.debugForceReleaseMode = true;
      AmbulanceEnabled.debugOverride = false;
      FirebaseBootstrap.isReady = false;
    });

    tearDown(() {
      FirebaseBootstrap.isReady = false;
    });

    Future<void> pumpNoForbidden(WidgetTester tester, Widget home) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      Object? firestoreForbidden;
      await runZonedGuarded(() async {
        await tester.pumpWidget(MaterialApp(home: home));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
      }, (error, stack) {
        if (error is StateError &&
            error.message.contains('FIRESTORE_FORBIDDEN')) {
          firestoreForbidden = error;
        }
      });

      final taken = tester.takeException();
      if (taken is StateError && taken.message.contains('FIRESTORE_FORBIDDEN')) {
        firestoreForbidden = taken;
      }

      expect(
        firestoreForbidden,
        isNull,
        reason: 'launch screen must not reach client Firestore in release',
      );
    }

    testWidgets('WelcomeScreen', (tester) async {
      await pumpNoForbidden(tester, const WelcomeScreen());
    });

    testWidgets('DoctorSearchScreen', (tester) async {
      PatientProfileMock.profileAddress =
          const PatientAddress(city: 'Mumbai', pincode: '400001');
      await pumpNoForbidden(tester, const DoctorSearchScreen());
    });

    testWidgets('PatientHomeScreen', (tester) async {
      await pumpNoForbidden(tester, const PatientHomeScreen());
    });

    testWidgets('DoctorVerificationGate', (tester) async {
      await pumpNoForbidden(
        tester,
        const DoctorVerificationGate(
          doctorId: 'doc-smoke-1',
          verifiedChildOverride: SizedBox(key: Key('verified')),
        ),
      );
    });

    testWidgets('DoctorVerificationPendingScreen', (tester) async {
      await pumpNoForbidden(
        tester,
        const DoctorVerificationPendingScreen(),
      );
    });
  });
}
