import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/theme/app_colors.dart';
import 'package:medibond/core/theme/app_theme.dart';
import 'package:medibond/features/ambulance/ambulance_booking_screen.dart';
import 'package:medibond/features/ambulance/models/ambulance_models.dart';
import 'package:medibond/features/patient/lab/my_labs_screen.dart';
import 'package:medibond/features/patient/widgets/patient_app_shell.dart';
import 'package:medibond/features/shared/screens/patient_profile_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Patient shell bottom navigation', () {
    testWidgets(
        'IndexedStack tab switches keep PatientAppShell bottom bar visible',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      var selectedIndex = 0;

      Future<void> pumpShell() async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(AppColors.patientTeal),
            home: StatefulBuilder(
              builder: (context, setState) {
                return PatientAppShell(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (index) {
                    setState(() => selectedIndex = index);
                  },
                  tabs: const [
                    PatientTabItem(
                      outlinedIcon: Icons.home_outlined,
                      filledIcon: Icons.home_rounded,
                      label: 'Home',
                    ),
                    PatientTabItem(
                      outlinedIcon: Icons.event_outlined,
                      filledIcon: Icons.event_rounded,
                      label: 'Appointments',
                      shortLabel: 'Visits',
                    ),
                    PatientTabItem(
                      outlinedIcon: Icons.science_outlined,
                      filledIcon: Icons.science_rounded,
                      label: 'My Labs',
                      shortLabel: 'Labs',
                    ),
                    PatientTabItem(
                      outlinedIcon: Icons.local_hospital_outlined,
                      filledIcon: Icons.local_hospital_rounded,
                      label: 'Ambulance',
                    ),
                    PatientTabItem(
                      outlinedIcon: Icons.person_outline_rounded,
                      filledIcon: Icons.person_rounded,
                      label: 'Profile',
                    ),
                  ],
                  child: IndexedStack(
                    index: selectedIndex,
                    children: const [
                      Scaffold(body: Center(child: Text('Home Screen'))),
                      Scaffold(body: Center(child: Text('Visits Screen'))),
                      MyLabsScreen(embeddedInShell: true),
                      AmbulanceBookingScreen(
                        bookedByRole: AmbulanceBookedByRole.patient,
                        embeddedInShell: true,
                      ),
                      PatientProfileScreen(embeddedInShell: true),
                    ],
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await pumpShell();
      expect(find.byType(PatientAppShell), findsOneWidget);

      for (final tabLabel in ['Labs', 'Ambulance', 'Visits', 'Profile']) {
        await tester.tap(find.text(tabLabel));
        await tester.pumpAndSettle();
        expect(find.byType(PatientAppShell), findsOneWidget,
            reason: 'Bottom nav should remain visible on $tabLabel');
      }

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Home Screen'), findsOneWidget);
      expect(find.byType(PatientAppShell), findsOneWidget);
    });

    testWidgets('embedded shell tab screens hide AppBar back affordance',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: MyLabsScreen(embeddedInShell: true),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('My Lab'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsNothing);

      await tester.pumpWidget(
        const MaterialApp(
          home: AmbulanceBookingScreen(
            bookedByRole: AmbulanceBookedByRole.patient,
            embeddedInShell: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Emergency Ambulance'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });
  });
}
