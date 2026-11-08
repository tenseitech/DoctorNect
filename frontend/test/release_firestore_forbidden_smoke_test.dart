import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/config/ambulance_enabled.dart';
import 'package:medibond/core/config/firestore_forbidden_guard.dart';
import 'package:medibond/core/firebase/firebase_bootstrap.dart';
import 'package:medibond/core/firebase/firestore_service.dart';
import 'package:medibond/core/firebase/firestore_ui.dart';
import 'package:medibond/core/session/doctor_session.dart';
import 'package:medibond/core/supabase/supabase_bootstrap.dart';
import 'package:medibond/core/supabase/supabase_stream_table.dart';
import 'package:medibond/core/theme/app_colors.dart';
import 'package:medibond/core/theme/app_theme.dart';
import 'package:medibond/features/doctor/appointments/doctor_appointments_screen.dart';
import 'package:medibond/features/doctor/home/doctor_home_screen.dart';
import 'package:medibond/features/doctor/lab/doctor_connected_labs_screen.dart';
import 'package:medibond/features/doctor/pharmacy/doctor_connected_stores_screen.dart';
import 'package:medibond/features/doctor/profile/data/doctor_profile_store.dart';
import 'package:medibond/features/doctor/models/doctor_models.dart';
import 'package:medibond/features/doctor/profile/models/doctor_profile_data.dart';
import 'package:medibond/features/doctor/verification/doctor_verification_gate.dart';
import 'package:medibond/features/doctor/verification/doctor_verification_pending_screen.dart';
import 'package:medibond/features/lab/lab_shell.dart';
import 'package:medibond/features/patient/booking/booking_flow_screen.dart';
import 'package:medibond/features/patient/home/patient_home_screen.dart';
import 'package:medibond/features/patient/lab/lab_booking_flow_screen.dart';
import 'package:medibond/features/patient/lab/lab_home_screen.dart';
import 'package:medibond/features/patient/lab/models/lab_models.dart';
import 'package:medibond/features/patient/lab/my_labs_screen.dart';
import 'package:medibond/features/patient/profile/data/patient_profile_mock.dart';
import 'package:medibond/features/patient/profile/edit_profile_screen.dart';
import 'package:medibond/features/patient/profile/models/patient_profile_models.dart';
import 'package:medibond/features/patient/search/doctor_search_screen.dart';
import 'package:medibond/features/pharmacy/medical_store_shell.dart';
import 'package:medibond/features/welcome/welcome_screen.dart';

void main() {
  tearDown(() {
    FirestoreForbiddenGuard.resetForTesting();
    AmbulanceEnabled.resetForTesting();
    PatientProfileMock.reset();
    SupabaseBootstrap.resetForTesting();
    debugTableFetcher = null;
    DoctorSession.clear();
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

  group('MIGRATED launch entry screens (release guard + fake Supabase)', () {
    setUp(() {
      FirestoreForbiddenGuard.resetForTesting();
      FirestoreForbiddenGuard.debugForceReleaseMode = true;
      AmbulanceEnabled.debugOverride = false;
      FirebaseBootstrap.isReady = false;
      SupabaseBootstrap.isReady = true;
      debugTableFetcher = (_) async => [];
    });

    tearDown(() {
      FirebaseBootstrap.isReady = false;
      SupabaseBootstrap.isReady = false;
      debugTableFetcher = null;
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

    testWidgets('patient login/registration WelcomeScreen', (tester) async {
      await pumpNoForbidden(tester, const WelcomeScreen());
    });

    testWidgets('patient home PatientHomeScreen', (tester) async {
      await pumpNoForbidden(tester, const PatientHomeScreen());
    });

    testWidgets('patient appointment BookingFlowScreen', (tester) async {
      PatientProfileMock.profileAddress =
          const PatientAddress(city: 'Mumbai', pincode: '400001');
      await pumpNoForbidden(
        tester,
        const BookingFlowScreen(doctorId: 'doc-smoke-1'),
      );
    });

    testWidgets('patient search DoctorSearchScreen', (tester) async {
      PatientProfileMock.profileAddress =
          const PatientAddress(city: 'Mumbai', pincode: '400001');
      await pumpNoForbidden(tester, const DoctorSearchScreen());
    });

    testWidgets('patient lab hub MyLabsScreen', (tester) async {
      await pumpNoForbidden(tester, const MyLabsScreen());
    });

    testWidgets('patient lab browse LabHomeScreen', (tester) async {
      await pumpNoForbidden(tester, const LabHomeScreen());
    });

    testWidgets('patient lab order LabBookingFlowScreen', (tester) async {
      await pumpNoForbidden(
        tester,
        LabBookingFlowScreen(
          tests: const [
            LabTestItem(
              id: 't-smoke-1',
              name: 'CBC',
              parameters: ['Hb'],
              fastingRequired: false,
              sampleType: SampleType.blood,
              reportHours: 24,
              category: 'Blood',
            ),
          ],
        ),
      );
    });

    testWidgets('patient profile EditProfileScreen', (tester) async {
      await pumpNoForbidden(
        tester,
        EditProfileScreen(
          profile: PatientProfile(
            name: 'Smoke Patient',
            age: 30,
            gender: 'Male',
            bloodGroup: 'O+',
            mobile: '9876543210',
            email: 'smoke@test.com',
          ),
          onSaved: () {},
        ),
      );
    });

    testWidgets('doctor gate DoctorVerificationGate', (tester) async {
      await pumpNoForbidden(
        tester,
        const DoctorVerificationGate(
          doctorId: 'doc-smoke-1',
          verifiedChildOverride: SizedBox(key: Key('verified')),
        ),
      );
    });

    testWidgets('doctor pending DoctorVerificationPendingScreen', (tester) async {
      await pumpNoForbidden(
        tester,
        const DoctorVerificationPendingScreen(),
      );
    });

    testWidgets('doctor home DoctorHomeScreen', (tester) async {
      DoctorSession.setDoctor(id: 'doc-smoke-1', name: 'Dr Smoke');
      DoctorProfileStore.instance.profile = DoctorProfileData(
        fullName: 'Dr Smoke',
        specialization: 'General',
        verificationStatus: VerificationStatus.verified,
        rating: 4.5,
        reviewCount: 1,
        city: 'Mumbai',
      );
      await pumpNoForbidden(
        tester,
        MaterialApp(
          theme: AppTheme.light(AppColors.doctorBlue),
          home: const DoctorHomeScreen(),
        ),
      );
    });

    testWidgets('doctor connected labs DoctorConnectedLabsScreen', (tester) async {
      DoctorSession.setDoctor(id: 'doc-smoke-1', name: 'Dr Smoke');
      await pumpNoForbidden(
        tester,
        MaterialApp(
          theme: AppTheme.light(AppColors.doctorBlue),
          home: const DoctorConnectedLabsScreen(showAppBar: false),
        ),
      );
    });

    testWidgets('doctor appointments DoctorAppointmentsScreen', (tester) async {
      await pumpNoForbidden(
        tester,
        MaterialApp(
          theme: AppTheme.light(AppColors.doctorBlue),
          home: const DoctorAppointmentsScreen(),
        ),
      );
    });

    testWidgets('doctor pharmacy partners DoctorConnectedStoresScreen', (tester) async {
      DoctorSession.setDoctor(id: 'doc-smoke-1', name: 'Dr Smoke');
      DoctorProfileStore.instance.profile = DoctorProfileData(
        fullName: 'Dr Smoke',
        specialization: 'General',
        verificationStatus: VerificationStatus.verified,
        rating: 4.5,
        reviewCount: 1,
        city: 'Mumbai',
      );
      await pumpNoForbidden(
        tester,
        MaterialApp(
          theme: AppTheme.light(AppColors.doctorBlue),
          home: const Scaffold(
            body: DoctorConnectedStoresScreen(showAppBar: false),
          ),
        ),
      );
    });

    testWidgets('pharmacy shell MedicalStoreShell', (tester) async {
      await pumpNoForbidden(
        tester,
        MaterialApp(
          theme: AppTheme.light(AppColors.pharmacyGreen),
          home: const MedicalStoreShell(),
        ),
      );
    });

    testWidgets('lab module LabShell', (tester) async {
      await pumpNoForbidden(
        tester,
        MaterialApp(
          theme: AppTheme.light(AppColors.labPurple),
          home: const LabShell(),
        ),
      );
    });
  });
}
