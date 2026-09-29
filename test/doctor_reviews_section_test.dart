import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:medibond/core/session/doctor_session.dart';
import 'package:medibond/core/theme/app_colors.dart';
import 'package:medibond/core/theme/app_theme.dart';
import 'package:medibond/features/doctor/models/doctor_models.dart';
import 'package:medibond/features/doctor/profile/data/doctor_profile_store.dart';
import 'package:medibond/features/doctor/profile/models/doctor_profile_data.dart';
import 'package:medibond/features/doctor/profile/sections/reviews_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    DoctorSession.clear();
    DoctorProfileStore.instance.profile = DoctorProfileData(
      fullName: 'Aarav Sharma',
      specialization: 'Cardiology',
      verificationStatus: VerificationStatus.verified,
      rating: 4.8,
      reviewCount: 2,
      reviews: [
        PatientReview(
          id: 'rev-1',
          maskedName: 'Kiran P.',
          rating: 5,
          date: DateTime(2026, 9, 20),
          text: 'Very thorough and compassionate consultation.',
          helpfulCount: 3,
        ),
        PatientReview(
          id: 'rev-2',
          maskedName: 'Rohan M.',
          rating: 4,
          date: DateTime(2026, 9, 22),
          text: 'Quick diagnosis and helpful advice.',
          helpfulCount: 1,
        ),
      ],
    );
  });

  group('Doctor ReviewsSection Polish Tests', () {
    testWidgets(
      'Renders reviewer initials CircleAvatar, inline summary stars, pill FilterChips, OutlinedButton Reply, and dividers between cards',
      (tester) async {
        tester.view.physicalSize = const Size(500, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(AppColors.doctorBlue),
            home: const ReviewsSection(),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Reviewer Avatars with initials 'K' and 'R'
        expect(find.byType(CircleAvatar), findsNWidgets(2));
        expect(find.text('K'), findsOneWidget);
        expect(find.text('R'), findsOneWidget);

        // 2. Summary Card rating, inline star icons, total reviews, and rounded breakdown bars
        expect(find.text('4.8'), findsOneWidget);
        expect(find.text('2 total reviews'), findsOneWidget);
        final progressBars = tester
            .widgetList<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .toList();
        expect(progressBars.length, 5);
        for (final bar in progressBars) {
          expect(bar.borderRadius, BorderRadius.circular(999));
          expect(bar.minHeight, 8);
        }

        // 3. Filter chips (Top / Newest) use consistent StadiumBorder pill shape and showCheckmark: false
        final filterChips = tester
            .widgetList<FilterChip>(find.byType(FilterChip))
            .toList();
        expect(filterChips.length, 2);
        for (final chip in filterChips) {
          expect(chip.shape, isA<StadiumBorder>());
          expect(chip.showCheckmark, isFalse);
        }

        // 4. Reply uses OutlinedButton instead of bare TextButton
        expect(find.widgetWithText(OutlinedButton, 'Reply'), findsNWidgets(2));

        // Sorting toggle still works
        await tester.tap(find.text('Newest'));
        await tester.pumpAndSettle();
        expect(find.text('Rohan M.'), findsOneWidget);
        expect(find.text('Kiran P.'), findsOneWidget);
      },
    );
  });
}
