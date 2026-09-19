import 'package:medibond/core/firebase/firestore_service.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/enums/user_type.dart';
import 'package:medibond/core/firebase/firebase_bootstrap.dart';
import 'package:medibond/core/session/doctor_session.dart';
import 'package:medibond/features/doctor/verification/doctor_verification_gate.dart';
import 'package:medibond/features/doctor/verification/doctor_verification_pending_screen.dart';

void main() {
  const doctorId = 'doc-test-001';

  tearDown(() {
    DoctorVerificationRepository.debugReset();
    FirebaseBootstrap.isReady = false;
    DoctorSession.clear();
  });

  group('DoctorVerificationRepository.parseVerifiedFromDoctorData', () {
    test('true bool is verified', () {
      expect(
        DoctorVerificationRepository.parseVerifiedFromDoctorData(
            {'verified': true}),
        isTrue,
      );
    });

    test('string "true" is verified', () {
      expect(
        DoctorVerificationRepository.parseVerifiedFromDoctorData(
            {'verified': 'true'}),
        isTrue,
      );
      expect(
        DoctorVerificationRepository.parseVerifiedFromDoctorData(
            {'verified': 'True'}),
        isTrue,
      );
    });

    test('false, missing, or null data is not verified', () {
      expect(
        DoctorVerificationRepository.parseVerifiedFromDoctorData(
            {'verified': false}),
        isFalse,
      );
      expect(
        DoctorVerificationRepository.parseVerifiedFromDoctorData(
            {'verified': 'false'}),
        isFalse,
      );
      expect(
        DoctorVerificationRepository.parseVerifiedFromDoctorData({}),
        isFalse,
      );
      expect(
        DoctorVerificationRepository.parseVerifiedFromDoctorData(null),
        isFalse,
      );
    });
  });

  group('DoctorVerificationRepository.watchVerified guards', () {
    test('returns false when Firebase is unavailable', () async {
      FirebaseBootstrap.isReady = false;
      final values = await DoctorVerificationRepository.instance
          .watchVerified(doctorId)
          .toList();
      expect(values, [false]);
    });

    test('returns false for empty doctor id', () async {
      FirebaseBootstrap.isReady = true;
      final values = await DoctorVerificationRepository.instance
          .watchVerified('')
          .toList();
      expect(values, [false]);
    });

    test('uses debug override stream in tests', () async {
      final controller = StreamController<bool>();
      DoctorVerificationRepository.debugWatchVerifiedOverride =
          (_) => controller.stream;

      final pending =
          DoctorVerificationRepository.instance.watchVerified(doctorId);
      final valuesFuture = pending.take(2).toList();

      controller.add(false);
      controller.add(true);
      await controller.close();

      expect(await valuesFuture, [false, true]);
    });
  });

  group('FirestoreService.instance.doctorAccount.isVerified guards', () {
    test('returns false when Firebase is unavailable', () async {
      FirebaseBootstrap.isReady = false;
      final verified =
          await FirestoreService.instance.doctorAccount.isVerified(doctorId);
      expect(verified, isFalse);
    });
  });

  group('RoleAccountRepository doctor routing', () {
    test('doctor role delegates to DoctorAccountRepository', () async {
      FirebaseBootstrap.isReady = false;
      final verified = await FirestoreService.instance.roleAccount.isVerified(
        UserType.doctor,
        doctorId,
      );
      expect(verified, isFalse);
    });

    test('under-review login message is defined for non-doctor roles', () {
      expect(
        RoleAccountRepository.underReviewLoginMessage,
        contains('under review'),
      );
    });
  });

  group('DoctorVerificationGate widget', () {
    Future<void> pumpGate(
      WidgetTester tester, {
      required String id,
      Stream<bool>? stream,
      Widget? verifiedChildOverride,
    }) async {
      if (stream != null) {
        DoctorVerificationRepository.debugWatchVerifiedOverride = (_) => stream;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: DoctorVerificationGate(
            doctorId: id,
            verifiedChildOverride: verifiedChildOverride,
          ),
        ),
      );
    }

    testWidgets('empty doctor id shows loading indicator', (tester) async {
      await pumpGate(tester, id: '');
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('verified stream routes to verified child', (tester) async {
      const verifiedMarker = Key('verified-route');

      await pumpGate(
        tester,
        id: doctorId,
        stream: Stream<bool>.value(true),
        verifiedChildOverride: const SizedBox(key: verifiedMarker),
      );
      await tester.pump();

      expect(find.byKey(verifiedMarker), findsOneWidget);
      expect(find.text('Verification pending'), findsNothing);
    });
  });

  group('DoctorVerificationPendingScreen widget', () {
    testWidgets('shows greeting and support actions', (tester) async {
      DoctorSession.setDoctor(id: doctorId, name: 'Dr Priya');

      await tester.pumpWidget(
        const MaterialApp(
          home: DoctorVerificationPendingScreen(),
        ),
      );
      await tester.pump();

      expect(find.text('Verification pending'), findsOneWidget);
      expect(find.text('Hello, Dr Priya'), findsOneWidget);
      expect(find.text(DoctorVerificationPendingScreen.supportEmail),
          findsOneWidget);
      expect(find.text('Contact support'), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);
    });

    testWidgets('copy support email button is tappable', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: DoctorVerificationPendingScreen(),
        ),
      );
      await tester.pump();

      final copyButton = find.byIcon(Icons.copy_rounded);
      expect(copyButton, findsOneWidget);
      await tester.tap(copyButton);
      await tester.pump();
    });
  });
}
