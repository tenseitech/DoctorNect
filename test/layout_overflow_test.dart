import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/enums/user_type.dart';
import 'package:medibond/core/session/doctor_session.dart';
import 'package:medibond/core/theme/app_colors.dart';
import 'package:medibond/core/theme/app_theme.dart';
import 'package:medibond/features/ambulance/ambulance_booking_screen.dart';
import 'package:medibond/features/ambulance/models/ambulance_models.dart';
import 'package:medibond/features/auth/unified_auth_intro_screen.dart';
import 'package:medibond/features/doctor/clinical/models/clinical_models.dart';
import 'package:medibond/features/doctor/clinical/prescription/write_prescription_screen.dart';
import 'package:medibond/features/doctor/home/widgets/doctor_home_sections.dart';
import 'package:medibond/features/doctor/verification/doctor_verification_pending_screen.dart';
import 'package:medibond/features/patient/lab/lab_booking_confirmed_screen.dart';
import 'package:medibond/features/patient/lab/models/lab_models.dart';
import 'package:medibond/features/splash/splash_screen.dart';
import 'package:medibond/widgets/medibond_logo.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ViewportConfig {
  final String name;
  final Size size;
  final double dpr;
  final double textScale;

  const ViewportConfig({
    required this.name,
    required this.size,
    required this.dpr,
    required this.textScale,
  });
}

const kTestConfigs = [
  ViewportConfig(
    name: 'a) 360x640 (dpr 3.0, scale 1.0)',
    size: Size(360, 640),
    dpr: 3.0,
    textScale: 1.0,
  ),
  ViewportConfig(
    name: 'b) 360x640 (dpr 1.0, scale 1.3)',
    size: Size(360, 640),
    dpr: 1.0,
    textScale: 1.3,
  ),
  ViewportConfig(
    name: 'c) 411x891 (dpr 1.0, scale 1.3)',
    size: Size(411, 891),
    dpr: 1.0,
    textScale: 1.3,
  ),
  ViewportConfig(
    name: 'd) 800x1280 tablet (dpr 1.0, scale 1.0)',
    size: Size(800, 1280),
    dpr: 1.0,
    textScale: 1.0,
  ),
];

Future<void> _pumpScreen(
  WidgetTester tester,
  ViewportConfig config,
  Widget Function(BuildContext) builder, {
  Duration pumpDuration = const Duration(milliseconds: 100),
  Future<void> Function(WidgetTester)? action,
}) async {
  tester.view.physicalSize = Size(
    config.size.width * config.dpr,
    config.size.height * config.dpr,
  );
  tester.view.devicePixelRatio = config.dpr;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(AppColors.doctorBlue),
      home: MediaQuery(
        data: MediaQueryData(
          size: config.size,
          devicePixelRatio: config.dpr,
          textScaler: TextScaler.linear(config.textScale),
        ),
        child: Builder(builder: builder),
      ),
    ),
  );
  await tester.pump(pumpDuration);
  if (action != null) {
    await action(tester);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Layout Overflow Verification (4 Viewport Configurations)', () {
    // 1. Splash Screen
    for (final config in kTestConfigs) {
      testWidgets('SplashScreen layout - ${config.name}', (tester) async {
        await _pumpScreen(
          tester,
          config,
          (context) => const SplashScreen(),
          pumpDuration: Duration.zero,
        );
        expect(find.byType(DoctorNectLogo), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    // 2. Login / Auth Intro Screen
    for (final config in kTestConfigs) {
      testWidgets('UnifiedAuthIntroScreen layout - ${config.name}',
          (tester) async {
        await _pumpScreen(
          tester,
          config,
          (context) => const UnifiedAuthIntroScreen(role: UserType.patient),
          pumpDuration: const Duration(milliseconds: 100),
        );
        expect(find.byType(UnifiedAuthIntroScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    // 3. Doctor Verification Pending Screen
    for (final config in kTestConfigs) {
      testWidgets('DoctorVerificationPendingScreen layout - ${config.name}',
          (tester) async {
        DoctorSession.setDoctor(id: 'doc-verify-01', name: 'Dr. Ananya Roy');
        addTearDown(DoctorSession.clear);

        await _pumpScreen(
          tester,
          config,
          (context) => const DoctorVerificationPendingScreen(),
          pumpDuration: const Duration(milliseconds: 100),
        );
        expect(find.byType(DoctorVerificationPendingScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    // 4. Lab Booking Confirmed Screen
    for (final config in kTestConfigs) {
      testWidgets('LabBookingConfirmedScreen layout - ${config.name}',
          (tester) async {
        final booking = ConfirmedLabBooking(
          bookingId: 'LBK-5432',
          testName: 'Lipid Profile & Glucose Fasting',
          date: DateTime(2026, 10, 10),
          slotLabel: '07:30 AM - 08:30 AM',
          isHomeCollection: true,
          address: 'Flat 12B, Ocean View, Worli, Mumbai',
          awaitingLabApproval: false,
        );

        await _pumpScreen(
          tester,
          config,
          (context) => LabBookingConfirmedScreen(booking: booking),
          pumpDuration: const Duration(milliseconds: 100),
        );
        expect(find.byType(LabBookingConfirmedScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    // 5. Write Prescription Screen
    for (final config in kTestConfigs) {
      testWidgets('WritePrescriptionScreen layout - ${config.name}',
          (tester) async {
        const patient = PatientClinicalContext(
          patientName: 'Devendra Patel',
          age: 42,
          gender: 'Male',
        );

        await _pumpScreen(
          tester,
          config,
          (context) => const Scaffold(
            body: WritePrescriptionScreen(patient: patient),
          ),
          pumpDuration: const Duration(seconds: 2),
        );
        expect(find.byType(WritePrescriptionScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    // 6. Clinical Tools Bottom Sheet / Drawer
    for (final config in kTestConfigs) {
      testWidgets('ClinicalToolsDrawer layout - ${config.name}',
          (tester) async {
        await _pumpScreen(
          tester,
          config,
          (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  ClinicalToolsDrawer.show(
                    context,
                    title: 'Clinical Tools',
                    services: [
                      DoctorHomeServiceItem(
                        label: 'Write Prescription',
                        subtitle: 'Create digital Rx',
                        icon: Icons.edit_note_rounded,
                        gradient: const [Colors.blue, Colors.indigo],
                        onTap: () {},
                      ),
                      DoctorHomeServiceItem(
                        label: 'Lab Orders',
                        subtitle: 'Order diagnostic tests',
                        icon: Icons.science_outlined,
                        gradient: const [Colors.purple, Colors.deepPurple],
                        onTap: () {},
                      ),
                      DoctorHomeServiceItem(
                        label: 'Referral Consult',
                        subtitle: 'Refer to specialist',
                        icon: Icons.share_rounded,
                        gradient: const [Colors.teal, Colors.cyan],
                        onTap: () {},
                      ),
                    ],
                  );
                },
                child: const Text('Open Tools'),
              ),
            ),
          ),
          action: (tester) async {
            await tester.tap(find.text('Open Tools'));
            await tester.pumpAndSettle();
          },
        );
        expect(find.text('Clinical Tools'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    // 7. Ambulance Booking Screen
    for (final config in kTestConfigs) {
      testWidgets('AmbulanceBookingScreen layout - ${config.name}',
          (tester) async {
        await _pumpScreen(
          tester,
          config,
          (context) => const AmbulanceBookingScreen(
            bookedByRole: AmbulanceBookedByRole.patient,
          ),
          pumpDuration: const Duration(milliseconds: 500),
        );
        expect(find.byType(AmbulanceBookingScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
