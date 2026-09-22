import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/session/patient_session.dart';
import 'package:medibond/core/theme/app_colors.dart';
import 'package:medibond/core/theme/app_theme.dart';
import 'package:medibond/features/patient/patient_shell.dart';
import 'package:medibond/features/patient/profile/data/patient_photo_local_store.dart';
import 'package:medibond/features/patient/profile/data/patient_profile_mock.dart';
import 'package:medibond/features/patient/widgets/patient_app_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PatientProfileMock.reset();
    PatientSession.setPatient(id: 'patient_test_1', name: 'Kiran Patel');
    PatientProfileMock.profile.name = 'Kiran Patel';
    PatientProfileMock.profile.photoInitial = 'K';
    PatientProfileMock.profile.photoUrl = null;
  });

  tearDown(() {
    PatientProfileMock.reset();
    PatientSession.clear();
    PatientPhotoLocalStore.setCachedForTesting('patient_test_1', null);
  });

  group('Patient Profile Tab Avatar & Navigation Tests', () {
    testWidgets(
        'Profile tab avatar shows user initial fallback ("K") in circular teal container when no photo is set',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const Scaffold(
            body: Center(
              child: PatientProfileTabAvatar(
                selected: false,
                iconColor: Colors.grey,
                size: 28,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initial letter 'K' should be rendered in the avatar
      expect(find.text('K'), findsOneWidget);

      // Verify ClipOval is used to ensure circular crop
      expect(find.byType(ClipOval), findsOneWidget);
    });

    testWidgets(
        'Profile tab avatar updates initial dynamically when profile name updates',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const Scaffold(
            body: Center(
              child: PatientProfileTabAvatar(
                selected: false,
                iconColor: Colors.grey,
                size: 28,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('K'), findsOneWidget);

      // Change profile name to Amit and notify
      PatientProfileMock.profile.name = 'Amit Sharma';
      PatientProfileMock.profile.photoInitial = 'A';
      PatientProfileMock.notifyProfileUpdated();
      await tester.pumpAndSettle();

      // Now initial letter 'A' should be visible
      expect(find.text('A'), findsOneWidget);
      expect(find.text('K'), findsNothing);
    });

    testWidgets(
        'Profile tab avatar shows 2px teal ring in active state and subtle border in inactive state',
        (tester) async {
      // Inactive
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const Scaffold(
            body: Center(
              child: PatientProfileTabAvatar(
                selected: false,
                iconColor: Colors.grey,
                size: 28,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Container container = tester.widget<Container>(
        find
            .byWidgetPredicate(
              (w) =>
                  w is Container &&
                  w.decoration is BoxDecoration &&
                  (w.decoration as BoxDecoration).border != null,
            )
            .first,
      );
      BoxDecoration dec = container.decoration as BoxDecoration;
      Border border = dec.border as Border;
      expect(border.top.width, 1.0);

      // Active
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const Scaffold(
            body: Center(
              child: PatientProfileTabAvatar(
                selected: true,
                iconColor: Colors.white,
                size: 28,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      container = tester.widget<Container>(
        find
            .byWidgetPredicate(
              (w) =>
                  w is Container &&
                  w.decoration is BoxDecoration &&
                  (w.decoration as BoxDecoration).border != null,
            )
            .first,
      );
      dec = container.decoration as BoxDecoration;
      border = dec.border as Border;
      expect(border.top.color, AppColors.patientTeal);
      expect(border.top.width, 2.0);
    });

    testWidgets(
        'PatientBottomTabBar provides size 28 for Profile tab and soft teal active highlight',
        (tester) async {
      double? receivedSize;
      bool? receivedSelected;

      final testTabs = [
        const PatientTabItem(
          outlinedIcon: Icons.home_outlined,
          filledIcon: Icons.home_rounded,
          label: 'Home',
        ),
        PatientTabItem(
          outlinedIcon: Icons.person_outline_rounded,
          filledIcon: Icons.person_rounded,
          label: 'Profile',
          customIconBuilder: (context, selected, iconColor, size) {
            receivedSize = size;
            receivedSelected = selected;
            return SizedBox(width: size, height: size);
          },
        ),
      ];

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: Scaffold(
            body: PatientAppShell(
              selectedIndex: 1, // Profile selected
              onDestinationSelected: (_) {},
              tabs: testTabs,
              child: const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Mobile bottom bar should supply size 28 to Profile tab
      expect(receivedSize, 28.0);
      expect(receivedSelected, true);
    });

    testWidgets('PatientAppShell web sidebar provides size 32 for Profile tab',
        (tester) async {
      double? receivedSize;

      final testTabs = [
        const PatientTabItem(
          outlinedIcon: Icons.home_outlined,
          filledIcon: Icons.home_rounded,
          label: 'Home',
        ),
        PatientTabItem(
          outlinedIcon: Icons.person_outline_rounded,
          filledIcon: Icons.person_rounded,
          label: 'Profile',
          customIconBuilder: (context, selected, iconColor, size) {
            receivedSize = size;
            return SizedBox(width: size, height: size);
          },
        ),
      ];

      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: Scaffold(
            body: PatientAppShell(
              selectedIndex: 0,
              onDestinationSelected: (_) {},
              tabs: testTabs,
              child: const SizedBox(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Web sidebar should supply size 32 to Profile tab
      expect(receivedSize, 32.0);
    });

    testWidgets(
        'Profile tab avatar renders local cached bytes when available in PatientPhotoLocalStore',
        (tester) async {
      // Create a 1x1 transparent PNG byte array
      final testPngBytes = Uint8List.fromList([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0x00,
        0x00,
        0x00,
        0x0D,
        0x49,
        0x48,
        0x44,
        0x52,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        0x01,
        0x08,
        0x06,
        0x00,
        0x00,
        0x00,
        0x1F,
        0x15,
        0xC4,
        0x89,
        0x00,
        0x00,
        0x00,
        0x0A,
        0x49,
        0x44,
        0x41,
        0x54,
        0x78,
        0x9C,
        0x63,
        0x00,
        0x01,
        0x00,
        0x00,
        0x05,
        0x00,
        0x01,
        0x0D,
        0x0A,
        0x2D,
        0xB4,
        0x00,
        0x00,
        0x00,
        0x00,
        0x49,
        0x45,
        0x4E,
        0x44,
        0xAE,
        0x42,
        0x60,
        0x82
      ]);

      PatientPhotoLocalStore.setCachedForTesting(
          'patient_test_1', testPngBytes);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const Scaffold(
            body: Center(
              child: PatientProfileTabAvatar(
                selected: false,
                iconColor: Colors.grey,
                size: 28,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Image widget using MemoryImage should be rendered
      final imageFinder = find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is MemoryImage,
      );
      expect(imageFinder, findsOneWidget);

      // Verify BoxFit.cover is used
      final imageWidget = tester.widget<Image>(imageFinder.first);
      expect(imageWidget.fit, BoxFit.cover);
    });
  });
}
