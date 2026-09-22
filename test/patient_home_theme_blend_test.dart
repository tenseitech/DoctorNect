import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/theme/app_colors.dart';
import 'package:medibond/core/theme/app_theme.dart';
import 'package:medibond/features/patient/home/widgets/explore_section.dart';
import 'package:medibond/features/patient/home/widgets/services_section.dart';
import 'package:medibond/features/patient/widgets/patient_app_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Patient Home Background Theme Blend Tests', () {
    testWidgets(
        'ExploreSection has no conflicting surface ColoredBox and blends with scaffold',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(AppColors.patientTeal),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: ExploreSection(),
            ),
          ),
        ),
      );

      // ExploreSection root should be Padding directly, not ColoredBox
      final exploreFinder = find.byType(ExploreSection);
      expect(exploreFinder, findsOneWidget);

      final coloredBoxesUnderExplore = find.descendant(
        of: exploreFinder,
        matching: find.byType(ColoredBox),
      );
      // No ColoredBox should exist as background of ExploreSection
      expect(coloredBoxesUnderExplore, findsNothing);
    });

    testWidgets(
        'ServicesSection has no conflicting cardBg ColoredBox and blends with scaffold',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(AppColors.patientTeal),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ServicesSection(
                onServiceTap: (_) {},
              ),
            ),
          ),
        ),
      );

      final servicesFinder = find.byType(ServicesSection);
      expect(servicesFinder, findsOneWidget);

      final coloredBoxesUnderServices = find.descendant(
        of: servicesFinder,
        matching: find.byType(ColoredBox),
      );
      expect(coloredBoxesUnderServices, findsNothing);
    });

    testWidgets(
        'PatientAppShell uses matching scaffoldBackgroundColor in extended web mode',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(AppColors.patientTeal),
          home: PatientAppShell(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
            tabs: const [
              PatientTabItem(
                outlinedIcon: Icons.home_outlined,
                filledIcon: Icons.home,
                label: 'Home',
              ),
            ],
            child: const Text('Home Content'),
          ),
        ),
      );

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, AppColors.darkBackground);
    });
  });
}
