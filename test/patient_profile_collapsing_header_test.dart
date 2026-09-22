import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/theme/app_colors.dart';
import 'package:medibond/core/theme/app_theme.dart';
import 'package:medibond/features/patient/profile/data/patient_profile_mock.dart';
import 'package:medibond/features/shared/screens/patient_profile_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PatientProfileMock.profile.name = 'kp1';
    PatientProfileMock.profile.age = 26;
    PatientProfileMock.profile.gender = 'Male';
    PatientProfileMock.profile.mobile = '+91 9876543210';
    PatientProfileMock.profile.email = 'kp1@doctornect.test';
    PatientProfileMock.profile.height = 175;
    PatientProfileMock.profile.weight = 70;
  });

  group('Patient Profile Collapsing Header Tests', () {
    testWidgets('Header renders expanded with all details at top of scroll',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          darkTheme: AppTheme.dark(AppColors.patientTeal),
          home: const PatientProfileScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // CustomScrollView and SliverPersistentHeader must exist
      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.byType(SliverPersistentHeader), findsOneWidget);

      // Expanded state items
      expect(find.text('Profile'), findsWidgets);
      expect(find.text('Your account & health'), findsOneWidget);
      expect(find.text('kp1'), findsOneWidget);
      expect(find.text('26 yrs'), findsOneWidget);
      expect(find.text('Male'), findsOneWidget);
      expect(find.text('+91 9876543210'), findsOneWidget);
      expect(find.text('kp1@doctornect.test'), findsOneWidget);

      // Back arrow icon
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);

      // Normal scrollable content below header
      expect(find.text('Edit Profile'), findsOneWidget);
      expect(find.text('Family Profiles'), findsOneWidget);
    });

    testWidgets(
        'Header smoothly collapses on scroll down and pins slim bar with back button, avatar, and name',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(AppColors.patientTeal),
          home: const PatientProfileScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll down by 300 pixels
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();

      // Pinned bar should still show back arrow
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);

      // Name should still be visible in pinned bar
      expect(find.text('kp1'), findsOneWidget);

      // Subtitle 'Your account & health' should not be visible when collapsed
      final subtitleFinder = find.text('Your account & health');
      expect(subtitleFinder, findsNothing);

      // Scroll back up
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 300));
      await tester.pumpAndSettle();

      // Header expands back to full state
      expect(find.text('Your account & health'), findsOneWidget);
      expect(find.text('26 yrs'), findsOneWidget);
      expect(find.text('+91 9876543210'), findsOneWidget);
    });

    testWidgets('Collapsing header works seamlessly in web resolution',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const PatientProfileScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // CustomScrollView and collapsing header present on web
      expect(find.byType(CustomScrollView), findsOneWidget);
      expect(find.byType(SliverPersistentHeader), findsOneWidget);
      expect(find.text('kp1'), findsOneWidget);

      // Scroll down
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -250));
      await tester.pumpAndSettle();

      // Back arrow and name still pinned
      expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);
      expect(find.text('kp1'), findsOneWidget);
    });
  });
}
