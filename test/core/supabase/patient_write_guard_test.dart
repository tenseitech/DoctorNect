import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:medibond/core/supabase/patient_write_guard.dart';

void main() {
  setUp(() {
    PatientWriteGuard.resetForTesting();
  });

  tearDown(() {
    PatientWriteGuard.resetForTesting();
  });

  group('PatientWriteGuard UI & Failure Path Tests', () {
    testWidgets(
      'TEST 3A: Soft-switch intercept renders friendly maintenance bottom sheet',
      (WidgetTester tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(800, 1200);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // 1. Simulate maintenance flag active (allow_writes: false)
        PatientWriteGuard.debugMaintenanceOverride = true;

        bool writeExecuted = false;
        Object? thrownError;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () async {
                      try {
                        await PatientWriteGuard.run(
                          context: context,
                          action: () async {
                            writeExecuted = true;
                            return {'status': 'success'};
                          },
                        );
                      } catch (e) {
                        thrownError = e;
                      }
                    },
                    child: const Text('Book Appointment'),
                  );
                },
              ),
            ),
          ),
        );

        // Tap the book button
        await tester.tap(find.text('Book Appointment'));
        await tester.pumpAndSettle();

        // Assert write action was NEVER executed
        expect(
          writeExecuted,
          isFalse,
          reason: 'Write action must be blocked when maintenance is active',
        );

        // Assert PatientMaintenanceException was thrown
        expect(thrownError, isA<PatientMaintenanceException>());
        expect(
          (thrownError as PatientMaintenanceException).message,
          contains('DoctorNect is undergoing scheduled database maintenance'),
        );

        // Assert the friendly UI Bottom Sheet genuinely rendered
        expect(find.text('Scheduled System Maintenance'), findsOneWidget);
        expect(
          find.textContaining(
            'DoctorNect is currently undergoing a brief database maintenance update',
          ),
          findsOneWidget,
        );
        expect(find.text('Understand & Close'), findsOneWidget);

        // Dismiss the bottom sheet by tapping the button
        await tester.tap(find.text('Understand & Close'));
        await tester.pumpAndSettle();

        expect(find.text('Scheduled System Maintenance'), findsNothing);
      },
    );

    testWidgets(
      'TEST 3B: Safety-net timing-gap catches 42501 permission denied and renders friendly UI',
      (WidgetTester tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(800, 1200);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // 1. Simulate timing-gap: soft switch is not yet picked up (false)
        PatientWriteGuard.debugMaintenanceOverride = false;

        bool writeAttempted = false;
        Object? thrownError;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () async {
                      try {
                        await PatientWriteGuard.run(
                          context: context,
                          action: () async {
                            writeAttempted = true;
                            // Simulate hard 42501 permission denied from PostgREST freeze
                            throw const PostgrestException(
                              message:
                                  'permission denied for table appointments: database freeze active',
                              code: '42501',
                            );
                          },
                        );
                      } catch (e) {
                        thrownError = e;
                      }
                    },
                    child: const Text('Attempt Booking During Freeze'),
                  );
                },
              ),
            ),
          ),
        );

        // Tap the button to trigger write
        await tester.tap(find.text('Attempt Booking During Freeze'));
        await tester.pumpAndSettle();

        // Write was attempted because soft check passed
        expect(writeAttempted, isTrue);

        // Guard caught 42501 and converted it into a clean PatientMaintenanceException (NOT raw PostgrestException)
        expect(thrownError, isA<PatientMaintenanceException>());
        expect(
          thrownError is PostgrestException,
          isFalse,
          reason: 'Raw 42501 must NOT leak to client caller',
        );
        expect(
          (thrownError as PatientMaintenanceException).message,
          contains('Database write freeze active'),
        );

        // Assert the friendly UI Bottom Sheet rendered identically
        expect(find.text('Scheduled System Maintenance'), findsOneWidget);
        expect(find.text('Understand & Close'), findsOneWidget);

        // Verify that the maintenance state was cached immediately
        PatientWriteGuard.debugMaintenanceOverride = null;
        expect(await PatientWriteGuard.isMaintenanceActive(), isTrue);

        // Dismiss the bottom sheet
        await tester.tap(find.text('Understand & Close'));
        await tester.pumpAndSettle();
        expect(find.text('Scheduled System Maintenance'), findsNothing);
      },
    );

    testWidgets(
      'TEST 3C: Normal operation executes write without bottom sheet',
      (WidgetTester tester) async {
        PatientWriteGuard.debugMaintenanceOverride = false;

        bool writeExecuted = false;
        Map<String, dynamic>? result;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () async {
                      result = await PatientWriteGuard.run(
                        context: context,
                        action: () async {
                          writeExecuted = true;
                          return {
                            'appointment_id': 'apt-test-ok',
                            'status': 'confirmed',
                          };
                        },
                      );
                    },
                    child: const Text('Book Normally'),
                  );
                },
              ),
            ),
          ),
        );

        await tester.tap(find.text('Book Normally'));
        await tester.pumpAndSettle();

        expect(writeExecuted, isTrue);
        expect(result?['status'], 'confirmed');
        expect(find.text('Scheduled System Maintenance'), findsNothing);
      },
    );

    testWidgets(
      'TEST 3D: Profile update mutation timing-gap catches 42501 permission denied on patients table and renders friendly UI',
      (WidgetTester tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = const Size(800, 1200);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // 1. Simulate timing-gap: soft switch is not yet picked up
        PatientWriteGuard.debugMaintenanceOverride = false;

        bool profileWriteAttempted = false;
        Object? thrownError;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () async {
                      try {
                        await PatientWriteGuard.run(
                          context: context,
                          action: () async {
                            profileWriteAttempted = true;
                            // Simulate hard 42501 permission denied from PostgREST freeze on patients table
                            throw const PostgrestException(
                              message:
                                  'permission denied for table patients: database freeze active',
                              code: '42501',
                            );
                          },
                        );
                      } catch (e) {
                        thrownError = e;
                      }
                    },
                    child: const Text('Save Profile Changes'),
                  );
                },
              ),
            ),
          ),
        );

        // Tap 'Save Profile Changes'
        await tester.tap(find.text('Save Profile Changes'));
        await tester.pumpAndSettle();

        // Write was attempted because soft check passed
        expect(profileWriteAttempted, isTrue);

        // Guard caught 42501 and converted it into a clean PatientMaintenanceException (NOT raw PostgrestException)
        expect(thrownError, isA<PatientMaintenanceException>());
        expect(
          thrownError is PostgrestException,
          isFalse,
          reason: 'Raw 42501 must NOT leak to client caller on profile update',
        );
        expect(
          (thrownError as PatientMaintenanceException).message,
          contains('Database write freeze active'),
        );

        // Assert the friendly UI Bottom Sheet rendered
        expect(find.text('Scheduled System Maintenance'), findsOneWidget);
        expect(
          find.textContaining(
            'DoctorNect is currently undergoing a brief database maintenance update',
          ),
          findsOneWidget,
        );
        expect(find.text('Understand & Close'), findsOneWidget);

        // Verify that the maintenance state was cached immediately
        PatientWriteGuard.debugMaintenanceOverride = null;
        expect(await PatientWriteGuard.isMaintenanceActive(), isTrue);

        // Dismiss the bottom sheet
        await tester.tap(find.text('Understand & Close'));
        await tester.pumpAndSettle();
        expect(find.text('Scheduled System Maintenance'), findsNothing);
      },
    );

    testWidgets(
      'TEST 3E: Ordinary 42501 permission error does NOT trigger maintenance when freeze flag is inactive',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Soft check says system is NOT in maintenance
        PatientWriteGuard.debugMaintenanceOverride = false;

        bool writeAttempted = false;
        Object? thrownError;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () async {
                      try {
                        await PatientWriteGuard.run(
                          context: context,
                          action: () async {
                            writeAttempted = true;
                            // Ordinary application RLS violation (e.g. invalid patient_id or missing claim)
                            throw const PostgrestException(
                              message:
                                  'new row violates row-level security policy for table patients',
                              code: '42501',
                            );
                          },
                        );
                      } catch (e) {
                        thrownError = e;
                      }
                    },
                    child: const Text('Attempt Unauthorized Write'),
                  );
                },
              ),
            ),
          ),
        );

        await tester.tap(find.text('Attempt Unauthorized Write'));
        await tester.pumpAndSettle();

        expect(writeAttempted, isTrue);

        // Guard must rethrow raw PostgrestException instead of PatientMaintenanceException
        expect(thrownError, isA<PostgrestException>());
        expect(thrownError is PatientMaintenanceException, isFalse);

        // Friendly UI Bottom Sheet must NOT render
        expect(find.text('Scheduled System Maintenance'), findsNothing);

        // Maintenance state must NOT be cached as active
        expect(await PatientWriteGuard.isMaintenanceActive(), isFalse);
      },
    );

    testWidgets(
      'TEST 3F: Plain 42501 message with live freeze flag active shows the maintenance sheet',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        // Soft switch timing gap: initial cached check was false
        PatientWriteGuard.debugMaintenanceOverride = false;

        bool writeAttempted = false;
        Object? thrownError;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () async {
                      try {
                        await PatientWriteGuard.run(
                          context: context,
                          action: () async {
                            writeAttempted = true;
                            // Live freeze flag activates in database
                            PatientWriteGuard.debugMaintenanceOverride = true;
                            // Plain 42501 permission denied without "freeze" or "maintenance" in message
                            throw const PostgrestException(
                              message:
                                  'permission denied for table appointments',
                              code: '42501',
                            );
                          },
                        );
                      } catch (e) {
                        thrownError = e;
                      }
                    },
                    child: const Text('Attempt Write During Live Freeze'),
                  );
                },
              ),
            ),
          ),
        );

        await tester.tap(find.text('Attempt Write During Live Freeze'));
        await tester.pumpAndSettle();

        expect(writeAttempted, isTrue);

        // Guard must catch plain 42501 and map it to PatientMaintenanceException
        expect(thrownError, isA<PatientMaintenanceException>());

        // Friendly UI Bottom Sheet must render
        expect(find.text('Scheduled System Maintenance'), findsOneWidget);
        expect(find.text('Understand & Close'), findsOneWidget);

        // Maintenance state must now be cached as active
        expect(await PatientWriteGuard.isMaintenanceActive(), isTrue);

        // Dismiss the bottom sheet
        await tester.tap(find.text('Understand & Close'));
        await tester.pumpAndSettle();
        expect(find.text('Scheduled System Maintenance'), findsNothing);
      },
    );
  });
}
