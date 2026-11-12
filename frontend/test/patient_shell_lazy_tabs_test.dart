import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/theme/app_colors.dart';
import 'package:medibond/core/theme/app_theme.dart';
import 'package:medibond/features/ambulance/ambulance_booking_screen.dart';
import 'package:medibond/features/patient/appointments/patient_appointments_screen.dart';
import 'package:medibond/features/patient/home/patient_home_screen.dart';
import 'package:medibond/features/patient/lab/my_labs_screen.dart';
import 'package:medibond/features/patient/data/registered_doctors_store.dart';
import 'package:medibond/features/patient/patient_shell.dart';
import 'package:medibond/features/patient/widgets/patient_app_shell.dart';
import 'package:medibond/features/shared/screens/patient_profile_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    RegisteredDoctorsStore.instance.markStreamActiveForTesting(true);
  });

  tearDown(() {
    RegisteredDoctorsStore.instance.markStreamActiveForTesting(false);
  });

  group('PatientShell lazy tabs mounting', () {
    testWidgets(
      'only Home is built initially; selecting tab builds it once; switching back preserves state without reset',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(AppColors.patientTeal),
            home: const PatientShell(),
          ),
        );
        await tester.pump();

        // 1. Initial state: ONLY Home tab is built. Unvisited tabs do not exist in the widget tree at all.
        expect(find.byType(PatientAppShell), findsOneWidget);
        expect(find.byType(PatientHomeScreen), findsOneWidget);
        expect(
          find.byType(PatientAppointmentsScreen, skipOffstage: false),
          findsNothing,
        );
        expect(find.byType(MyLabsScreen, skipOffstage: false), findsNothing);
        expect(
          find.byType(AmbulanceBookingScreen, skipOffstage: false),
          findsNothing,
        );
        expect(
          find.byType(PatientProfileScreen, skipOffstage: false),
          findsNothing,
        );

        // 2. Select Appointment tab (index 1) via bottom nav icon
        await tester.tap(
          find.descendant(
            of: find.byType(PatientAppShell),
            matching: find.byIcon(Icons.event_outlined),
          ),
        );
        await tester.pumpAndSettle();

        // Appointment screen is now mounted and active on screen
        expect(find.byType(PatientAppointmentsScreen), findsOneWidget);
        // Other tabs remain completely unmounted
        expect(find.byType(MyLabsScreen, skipOffstage: false), findsNothing);
        expect(
          find.byType(AmbulanceBookingScreen, skipOffstage: false),
          findsNothing,
        );
        expect(
          find.byType(PatientProfileScreen, skipOffstage: false),
          findsNothing,
        );

        // Capture the state instance of the appointment screen
        final appointmentStateFirst = tester.state(
          find.byType(PatientAppointmentsScreen),
        );

        // 3. Switch back to Home tab (index 0)
        await tester.tap(
          find.descendant(
            of: find.byType(PatientAppShell),
            matching: find.byIcon(Icons.home_outlined),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(PatientHomeScreen), findsOneWidget);
        // In IndexedStack, visited Appointment screen is kept alive (offstage)
        expect(
          find.byType(PatientAppointmentsScreen, skipOffstage: false),
          findsOneWidget,
        );
        final appointmentStateAfterHome = tester.state(
          find.byType(PatientAppointmentsScreen, skipOffstage: false),
        );
        // State instance must be identical (not destroyed or rebuilt)
        expect(
          identical(appointmentStateFirst, appointmentStateAfterHome),
          isTrue,
        );

        // 4. Select Labs tab (index 2)
        await tester.tap(
          find.descendant(
            of: find.byType(PatientAppShell),
            matching: find.byIcon(Icons.science_outlined),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(MyLabsScreen), findsOneWidget);
        // Unvisited tabs remain unmounted
        expect(
          find.byType(AmbulanceBookingScreen, skipOffstage: false),
          findsNothing,
        );
        expect(
          find.byType(PatientProfileScreen, skipOffstage: false),
          findsNothing,
        );

        // 5. Switch back to Appointment tab (index 1)
        await tester.tap(
          find.descendant(
            of: find.byType(PatientAppShell),
            matching: find.byIcon(Icons.event_outlined),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(PatientAppointmentsScreen), findsOneWidget);
        final appointmentStateReturned = tester.state(
          find.byType(PatientAppointmentsScreen),
        );
        expect(
          identical(appointmentStateFirst, appointmentStateReturned),
          isTrue,
        );

        // Clean unmount
        await tester.pumpWidget(const SizedBox());
      },
    );
  });
}
