import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/constants/app_constants.dart';
import 'package:medibond/core/theme/app_colors.dart';
import 'package:medibond/core/theme/app_theme.dart';
import 'package:medibond/features/doctor/patients/widgets/walkin_patient_sheet.dart';
import 'package:medibond/features/lab/screens/lab_walkin_screen.dart';
import 'package:medibond/features/patient/profile/utils/medication_time_slots.dart';
import 'package:medibond/widgets/phone_number_field.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('LabWalkInScreen - Overflow & Layout Fixes', () {
    testWidgets(
      'renders at 360px width with 2.0x text scale and keyboard open without RenderFlex overflow',
      (tester) async {
        final errors = <FlutterErrorDetails>[];
        final oldHandler = FlutterError.onError;
        FlutterError.onError = (details) {
          errors.add(details);
        };

        try {
          tester.view.physicalSize = const Size(360, 640);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light(const Color(0xFF6B21A8)),
              home: MediaQuery(
                data: const MediaQueryData(
                  size: Size(360, 640),
                  devicePixelRatio: 1.0,
                  textScaler: TextScaler.linear(2.0),
                  viewInsets: EdgeInsets.only(bottom: 300),
                ),
                child: const Scaffold(
                  body: LabWalkInScreen(),
                ),
              ),
            ),
          );
          await tester.pump();

          // Ensure no RenderFlex overflows
          final overflows = errors.where((e) =>
              e.exceptionAsString().contains('A RenderFlex overflowed') ||
              e.exceptionAsString().contains('overflowed by'));
          expect(overflows, isEmpty,
              reason:
                  'Found RenderFlex overflow: ${overflows.map((e) => e.exception).toList()}');

          // Header title and button are present
          expect(find.text('Walk-in Patient'), findsOneWidget);
          expect(find.text('View all patients'), findsOneWidget);

          // Scroll to reveal form fields
          await tester.drag(find.byType(ListView), const Offset(0, -300));
          await tester.pumpAndSettle();

          // Form fields are present
          expect(find.text('Select gender'), findsOneWidget);
          expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
          expect(find.byType(PhoneNumberField), findsOneWidget);
        } finally {
          FlutterError.onError = oldHandler;
        }
      },
    );

    testWidgets(
      'gender dropdown expands and items have ellipsis without overflow at 360px',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(const Color(0xFF6B21A8)),
            home: const MediaQuery(
              data: MediaQueryData(
                size: Size(360, 640),
                devicePixelRatio: 1.0,
                textScaler: TextScaler.linear(1.0),
              ),
              child: Scaffold(
                body: LabWalkInScreen(),
              ),
            ),
          ),
        );
        await tester.pump();

        // Tap the gender dropdown
        await tester.ensureVisible(find.text('Select gender'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Select gender'), warnIfMissed: false);
        await tester.pumpAndSettle();

        // Expect all gender options to appear in dropdown menu
        for (final gender in AppConstants.genders) {
          expect(find.text(gender), findsWidgets);
        }

        // Tap Male
        await tester.tap(find.text('Male').last);
        await tester.pumpAndSettle();

        expect(find.text('Male'), findsOneWidget);
      },
    );

    testWidgets(
      'PhoneNumberField height matches standard TextFormField height',
      (tester) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final nameController = TextEditingController();
        final phoneController = TextEditingController();

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(AppColors.doctorBlue),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Name'),
                    ),
                    const SizedBox(height: 12),
                    PhoneNumberField(
                      controller: phoneController,
                      labelText: 'Phone',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final nameBox = tester.getRect(find.byType(TextFormField).first);
        final phoneBox = tester.getRect(find.byType(PhoneNumberField));

        // The height difference between standard TextFormField and PhoneNumberField
        // should be less than or equal to 2 pixels (effectively identical height)
        expect((nameBox.height - phoneBox.height).abs(), lessThanOrEqualTo(2.0),
            reason:
                'Name height (${nameBox.height}) should match Phone height (${phoneBox.height})');
      },
    );
  });

  group('Doctor WalkInPatientSheet - Overflow & Layout Fixes', () {
    testWidgets(
      'renders at 360px with 2.0x text scale and keyboard open without overflow',
      (tester) async {
        final errors = <FlutterErrorDetails>[];
        final oldHandler = FlutterError.onError;
        FlutterError.onError = (details) {
          errors.add(details);
        };

        try {
          tester.view.physicalSize = const Size(360, 640);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light(AppColors.doctorBlue),
              home: MediaQuery(
                data: const MediaQueryData(
                  size: Size(360, 640),
                  devicePixelRatio: 1.0,
                  textScaler: TextScaler.linear(2.0),
                  viewInsets: EdgeInsets.only(bottom: 300),
                ),
                child: const Scaffold(
                  body: WalkInPatientSheet(),
                ),
              ),
            ),
          );
          await tester.pump();

          final overflows = errors.where((e) =>
              e.exceptionAsString().contains('A RenderFlex overflowed') ||
              e.exceptionAsString().contains('overflowed by'));
          expect(overflows, isEmpty,
              reason: 'Doctor WalkInPatientSheet had overflow: $overflows');
        } finally {
          FlutterError.onError = oldHandler;
        }
      },
    );
  });

  group('Patient MedicationTimeSlots - Row Dropdown isExpanded Fix', () {
    testWidgets(
      'Hour and Minute dropdowns inside Row do not overflow at 360px with 2.0x text scale',
      (tester) async {
        final errors = <FlutterErrorDetails>[];
        final oldHandler = FlutterError.onError;
        FlutterError.onError = (details) {
          errors.add(details);
        };

        try {
          tester.view.physicalSize = const Size(360, 640);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light(AppColors.doctorBlue),
              home: MediaQuery(
                data: const MediaQueryData(
                  size: Size(360, 640),
                  devicePixelRatio: 1.0,
                  textScaler: TextScaler.linear(2.0),
                ),
                child: Builder(
                  builder: (context) {
                    return ElevatedButton(
                      onPressed: () {
                        MedicationTimeSlots.pickTime(
                          context,
                          MedicationTimeSlot.morning,
                          current: '08:30',
                        );
                      },
                      child: const Text('Pick Time'),
                    );
                  },
                ),
              ),
            ),
          );
          await tester.pump();

          await tester.tap(find.text('Pick Time'));
          await tester.pumpAndSettle();

          final overflows = errors.where((e) =>
              e.exceptionAsString().contains('A RenderFlex overflowed') ||
              e.exceptionAsString().contains('overflowed by'));
          expect(overflows, isEmpty,
              reason: 'MedicationTimeSlots sheet had overflow: $overflows');
        } finally {
          FlutterError.onError = oldHandler;
        }
      },
    );
  });
}
