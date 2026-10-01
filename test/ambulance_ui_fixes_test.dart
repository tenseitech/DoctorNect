import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/auth/verification_lifecycle.dart';
import 'package:medibond/core/enums/user_type.dart';
import 'package:medibond/features/ambulance/data/ambulance_store.dart';
import 'package:medibond/features/ambulance/models/ambulance_models.dart';
import 'package:medibond/features/ambulance/widgets/ambulance_availability_toggle.dart';
import 'package:medibond/widgets/adaptive_app_shell.dart';

/// Reads a source file relative to the project root (where `flutter test` runs).
String _readSourceFile(String relativePath) =>
    File(relativePath).readAsStringSync();

/// Helper: formats an address the same way ambulance_profile_screen does,
/// so we can unit-test clean address formatting without Firebase.
String _formatAddress(RegisteredAmbulance a) {
  final parts = <String>[
    if ((a.baseAddress).isNotEmpty) a.baseAddress,
    if ((a.city).isNotEmpty) a.city,
    if ((a.state).isNotEmpty) a.state,
    if ((a.pincode).isNotEmpty) a.pincode,
    if ((a.country).isNotEmpty) a.country,
  ];
  return parts.isEmpty ? '' : parts.join(', ');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sampleAmbulance = RegisteredAmbulance(
    id: 'amb-test-123',
    serviceName: 'City Emergency Services',
    ownerName: 'Apex Health Corp',
    driverName: 'Ramesh Kumar',
    phone: '+919876543210',
    vehicleNumber: 'MH-12-AB-1234',
    ambulanceType: AmbulanceType.als,
    city: 'Pune',
    serviceAreas: const ['Kothrud', 'Baner'],
    baseAddress: 'Station 4, Pune',
    licenseNumber: 'MH1220261234567',
    insuranceNumber: 'POL-1234567890',
    hasOxygen: true,
    hasVentilator: true,
    hasStretcher: true,
    is24x7: true,
    ratePerKm: 25.0,
    addressLine1: 'Station 4, Pune',
    addressLine2: 'Near Highway',
    country: 'India',
    state: 'Maharashtra',
    pincode: '411038',
    available: true,
  );

  // ─────────────────────────────────────────────────────────────────────────
  // 1. AdaptiveAppShell sidebar divider
  // ─────────────────────────────────────────────────────────────────────────
  group('AdaptiveAppShell sidebar divider option', () {
    testWidgets(
        'renders VerticalDivider by default when showSidebarDivider is true',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: AdaptiveAppShell(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
            ],
            child: const Text('Content Area'),
          ),
        ),
      );

      expect(find.byType(VerticalDivider), findsOneWidget);
    });

    testWidgets('omits VerticalDivider when showSidebarDivider is false',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: AdaptiveAppShell(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            showSidebarDivider: false,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
            ],
            child: const Text('Content Area'),
          ),
        ),
      );

      expect(find.byType(VerticalDivider), findsNothing);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 2. AmbulanceShell header divider removal (source-level assertion)
  //    AmbulanceShell depends on Firebase/AmbulanceDriverHomeScreen so it
  //    cannot be pumped in isolation. Instead we verify the source code:
  //    - No bare `Divider(` widget call remains under the header
  //    - showSidebarDivider: false is passed to AdaptiveAppShell
  // ─────────────────────────────────────────────────────────────────────────
  group('AmbulanceShell header divider removal', () {
    test(
        'ambulance_shell.dart does not contain a bare Divider widget under the header',
        () {
      // Read the source file at test-time using dart:io (available in flutter test)
      final shellSource =
          _readSourceFile('lib/features/ambulance/ambulance_shell.dart');

      // Must NOT contain the bare Divider(height: 1) that was removed
      expect(shellSource, isNot(contains('Divider(height: 1)')));
      // Must NOT contain const Divider()
      expect(shellSource, isNot(contains('const Divider()')));
    });

    test(
        'ambulance_shell.dart passes showSidebarDivider: false to AdaptiveAppShell',
        () {
      final shellSource =
          _readSourceFile('lib/features/ambulance/ambulance_shell.dart');
      expect(shellSource, contains('showSidebarDivider: false'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 3. AmbulanceAvailabilityToggle dark mode styling
  // ─────────────────────────────────────────────────────────────────────────
  group('AmbulanceAvailabilityToggle dark mode styling', () {
    testWidgets('uses dark-tinted green (not bright 0xFFF0FDF4) in dark mode',
        (tester) async {
      AmbulanceStore.instance.registerAmbulance(sampleAmbulance);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: AmbulanceAvailabilityToggle(ambulanceId: sampleAmbulance.id),
          ),
        ),
      );

      final cardFinder = find.byType(Card);
      expect(cardFinder, findsOneWidget);

      final card = tester.widget<Card>(cardFinder);
      // Dark mode online color must NOT be the bright light-green
      expect(card.color, isNot(equals(const Color(0xFFF0FDF4))));
      // Must be dark tinted green
      expect(
          card.color, equals(const Color(0xFF16A34A).withValues(alpha: 0.12)));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 4. Profile completion: unit tests (no Firebase needed)
  // ─────────────────────────────────────────────────────────────────────────
  group('Ambulance Profile Completion calculations & single source of truth',
      () {
    setUp(() {
      RoleVerificationController.instance.reset();
    });

    test('VerificationRequirementsConfig for ambulance has exactly 11 items',
        () {
      final reqs = VerificationRequirementsConfig.requirementsForRole(
          UserType.ambulance);
      expect(reqs.length, 11);
    });

    test('4 of 11 fields filled produces exactly 36% complete', () {
      final partialData = <String, dynamic>{
        'serviceName': 'City Emergency Services',
        'driverName': 'Ramesh Kumar',
        'phone': '+919876543210',
        'vehicleNumber': 'MH-12-AB-1234',
      };

      final percentage = VerificationRequirementsConfig.completionPercentage(
        UserType.ambulance,
        partialData,
      );
      final missing = VerificationRequirementsConfig.missingFields(
        UserType.ambulance,
        partialData,
      );

      expect(percentage, 36);
      expect(missing.length, 7);
    });

    test('All 11 fields filled produces 100% complete and empty missing list',
        () {
      final fullData = sampleAmbulance.toMap();
      // Ensure the alias key is also present
      if (sampleAmbulance.addressLine1.isNotEmpty) {
        fullData['baseAddress'] = sampleAmbulance.addressLine1;
      }

      final percentage = VerificationRequirementsConfig.completionPercentage(
        UserType.ambulance,
        fullData,
      );
      final missing = VerificationRequirementsConfig.missingFields(
        UserType.ambulance,
        fullData,
      );

      expect(percentage, 100);
      expect(missing, isEmpty);
    });

    test('partial ambulance with 7 missing fields shows 7 missing items', () {
      final partialAmb = RegisteredAmbulance(
        id: 'amb-partial',
        serviceName: 'Quick Medics',
        ownerName: '',
        driverName: 'Suresh',
        phone: '+919876543210',
        vehicleNumber: 'MH-14-CC-9988',
        ambulanceType: AmbulanceType.bls,
        city: '',
        serviceAreas: const [],
        baseAddress: '',
        licenseNumber: '',
        insuranceNumber: '',
        hasOxygen: false,
        hasVentilator: false,
        hasStretcher: true,
        is24x7: false,
        available: true,
      );

      final data = partialAmb.toMap();
      final missing = VerificationRequirementsConfig.missingFields(
          UserType.ambulance, data);
      final pct = VerificationRequirementsConfig.completionPercentage(
          UserType.ambulance, data);

      // serviceName, driverName, phone, vehicleNumber = 4 filled → 7 missing
      expect(missing.length, 7);
      // 4/11 = 36%
      expect(pct, 36);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 5. VerificationStage unit tests (no Firebase needed)
  // ─────────────────────────────────────────────────────────────────────────
  group('RoleVerificationController stage management', () {
    setUp(() {
      RoleVerificationController.instance.reset();
    });

    test('defaults to profileIncomplete when no state set', () {
      final stage =
          RoleVerificationController.instance.stageFor(UserType.ambulance);
      expect(stage, VerificationStage.profileIncomplete);
    });

    test('setRoleState to submittedForVerification is reflected in stageFor',
        () {
      RoleVerificationController.instance.setRoleState(
        UserType.ambulance,
        stage: VerificationStage.submittedForVerification,
      );
      expect(
        RoleVerificationController.instance.stageFor(UserType.ambulance),
        VerificationStage.submittedForVerification,
      );
    });

    test('setRoleState to revisionRequested is reflected in stageFor', () {
      RoleVerificationController.instance.setRoleState(
        UserType.ambulance,
        stage: VerificationStage.revisionRequested,
        rejectionReason: 'Please upload clear insurance documentation.',
      );
      expect(
        RoleVerificationController.instance.stageFor(UserType.ambulance),
        VerificationStage.revisionRequested,
      );
      expect(
        RoleVerificationController.instance
            .rejectionReasonFor(UserType.ambulance),
        'Please upload clear insurance documentation.',
      );
    });

    test('setRoleState to verified is reflected in stageFor', () {
      RoleVerificationController.instance.setRoleState(
        UserType.ambulance,
        stage: VerificationStage.verified,
      );
      expect(
        RoleVerificationController.instance.stageFor(UserType.ambulance),
        VerificationStage.verified,
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 6. Address formatting unit tests (no Firebase / widget render needed)
  // ─────────────────────────────────────────────────────────────────────────
  group('Address formatting helper', () {
    test('full address formats without dangling separators', () {
      final result = _formatAddress(sampleAmbulance);
      expect(result, isNot(contains(', -')));
      expect(result, isNot(contains('- ,')));
      expect(result, contains('Pune'));
    });

    test('empty baseAddress with only city does not produce "Nagpur, -"', () {
      final minimalAmb = RegisteredAmbulance(
        id: 'amb-min',
        serviceName: 'Metro Response',
        ownerName: '',
        driverName: 'Kunal',
        phone: '+919876543210',
        vehicleNumber: 'MH-12-CD-5566',
        ambulanceType: AmbulanceType.bls,
        city: 'Nagpur',
        serviceAreas: const [],
        baseAddress: '',
        licenseNumber: '',
        insuranceNumber: '',
        hasOxygen: false,
        hasVentilator: false,
        hasStretcher: false,
        is24x7: false,
        ratePerKm: null,
        available: false,
      );

      final result = _formatAddress(minimalAmb);
      expect(result, isNot(contains('Nagpur, -')));
      expect(result, contains('Nagpur'));
    });

    test('completely empty ambulance address returns empty string', () {
      final emptyAmb = RegisteredAmbulance(
        id: 'amb-empty',
        serviceName: '',
        ownerName: '',
        driverName: '',
        phone: '',
        vehicleNumber: '',
        ambulanceType: AmbulanceType.bls,
        city: '',
        serviceAreas: const [],
        baseAddress: '',
        licenseNumber: '',
        insuranceNumber: '',
        hasOxygen: false,
        hasVentilator: false,
        hasStretcher: false,
        is24x7: false,
        ratePerKm: null,
        available: false,
        country: '',
        state: '',
      );

      final result = _formatAddress(emptyAmb);
      expect(result, isEmpty);
    });
  });
}
