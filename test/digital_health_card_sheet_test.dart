import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/enums/user_type.dart';
import 'package:medibond/core/theme/app_colors.dart';
import 'package:medibond/core/theme/app_theme.dart';
import 'package:medibond/features/doctor/models/doctor_models.dart';
import 'package:medibond/features/doctor/profile/data/doctor_profile_store.dart';
import 'package:medibond/features/doctor/profile/models/doctor_profile_data.dart';
import 'package:medibond/widgets/digital_health_card_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    DoctorProfileStore.instance.profile = DoctorProfileData(
      fullName: 'k1',
      specialization: 'General Surgery',
      verificationStatus: VerificationStatus.verified,
      rating: 4.8,
      reviewCount: 12,
      councilNumber: 'MAH215165412',
      stateCouncil: 'Maharashtra',
    );
  });

  group('DigitalHealthCardSheet Tests', () {
    testWidgets(
      'Doctor credentials pass has NO "Scan to Verify Pass" section',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(AppColors.doctorBlue),
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => DigitalHealthCardSheet.show(
                    context,
                    userType: UserType.doctor,
                  ),
                  child: const Text('Open Pass'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open Pass'));
        await tester.pumpAndSettle();

        // Verify sheet title
        expect(find.text('Digital Doctor Credentials Pass'), findsOneWidget);

        // Verify Doctor Card details
        expect(find.text('DoctorNect PASS'), findsOneWidget);
        expect(find.text('VERIFIED'), findsOneWidget);
        expect(find.text('Dr. k1'), findsOneWidget);
        expect(find.text('General Surgery'), findsOneWidget);
        expect(find.text('REGISTRATION NO.'), findsOneWidget);
        expect(find.text('MAH215165412'), findsOneWidget);
        expect(find.text('COUNCIL'), findsOneWidget);
        expect(find.text('Maharashtra'), findsOneWidget);

        // Verify "Scan to Verify Pass" is REMOVED
        expect(find.text('Scan to Verify Pass'), findsNothing);
        expect(
          find.textContaining('Allows patients and pharmacies'),
          findsNothing,
        );

        // Verify action buttons
        expect(find.text('Share Pass'), findsOneWidget);
        expect(find.text('Done'), findsOneWidget);

        // Tap Done closes the sheet
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(find.text('Digital Doctor Credentials Pass'), findsNothing);
      },
    );

    testWidgets('Patient health card also has no "Scan to Verify Pass"', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => DigitalHealthCardSheet.show(
                  context,
                  userType: UserType.patient,
                ),
                child: const Text('Open Pass'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Pass'));
      await tester.pumpAndSettle();

      expect(find.text('Digital Health Card ID'), findsOneWidget);
      expect(find.text('Scan to Verify Pass'), findsNothing);
      expect(find.text('Share Pass'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
    });
  });
}
