import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/theme/app_colors.dart';
import 'package:medibond/core/theme/app_theme.dart';
import 'package:medibond/features/patient/data/patient_mock_data.dart';
import 'package:medibond/features/patient/data/registered_doctors_store.dart';
import 'package:medibond/features/patient/home/patient_home_screen.dart';
import 'package:medibond/features/patient/home/widgets/health_tips_section.dart';
import 'package:medibond/features/patient/models/patient_models.dart';
import 'package:medibond/widgets/home_banner_carousel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Patient Home Health Tips Removal & Carousel Behavior Tests', () {
    test('PatientMockData.healthTips is preserved for notification scheduler', () {
      expect(PatientMockData.healthTips.isNotEmpty, isTrue);
      expect(PatientMockData.healthTips.any((t) => t.title.contains('heart')), isTrue);
    });

    test('PatientMockData.carouselItems contains NO health tip slides', () {
      final healthTipSlides = PatientMockData.carouselItems
          .where((item) => item.banner.kind == HomeCarouselKind.healthTip)
          .toList();
      expect(healthTipSlides, isEmpty);

      // Only product/promotional slides remain
      for (final item in PatientMockData.carouselItems) {
        expect(item.banner.kind, equals(HomeCarouselKind.productAd));
      }
    });

    testWidgets('HomeBannerCarousel with 0 items returns SizedBox.shrink()',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeBannerCarousel(
              items: const [],
              dotActiveColor: AppColors.patientTeal,
            ),
          ),
        ),
      );

      expect(find.byType(PageView), findsNothing);
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('HomeBannerCarousel with 1 item hides dots and navigation buttons',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final singleItem = [
        const HomeCarouselItem(
          banner: PromoBanner(
            kind: HomeCarouselKind.productAd,
            title: 'Only Slide',
            subtitle: 'Only promo subtitle',
            gradientColors: [Color(0xFF1D4ED8), Color(0xFF3730A3)],
            icon: Icons.medical_services_outlined,
          ),
          ctaLabel: 'Learn more',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeBannerCarousel(
              items: singleItem,
              dotActiveColor: AppColors.patientTeal,
            ),
          ),
        ),
      );

      // PageView is present
      expect(find.byType(PageView), findsOneWidget);

      // Dots are NOT rendered when items.length <= 1
      expect(find.byType(Row), findsWidgets);
      // Verify no chevron navigation buttons
      expect(find.byIcon(Icons.chevron_left), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsNothing);

      // PageView has NeverScrollableScrollPhysics
      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.physics, isA<NeverScrollableScrollPhysics>());
    });

    testWidgets('HomeBannerCarousel with multiple items renders dynamic dots and nav buttons on wide screen',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeBannerCarousel(
              items: PatientMockData.carouselItems,
              dotActiveColor: AppColors.patientTeal,
            ),
          ),
        ),
      );

      // Both chevron navigation buttons are visible on wide screen with >1 items
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);

      // Scroll physics is normal (null / default)
      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.physics, isNull);
    });

    testWidgets('PatientHomeScreen does NOT render HealthTipsSection or health tip banners',
        (tester) async {
      RegisteredDoctorsStore.instance.markStreamActiveForTesting(true);
      addTearDown(() {
        RegisteredDoctorsStore.instance.markStreamActiveForTesting(false);
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const Scaffold(
            body: PatientHomeScreen(),
          ),
        ),
      );
      await tester.pump();

      // HealthTipsSection is NOT present
      expect(find.byType(HealthTipsSection), findsNothing);
      expect(find.text('Health tips'), findsNothing);
      expect(find.text('Quick reads for daily wellness'), findsNothing);
      expect(find.text('5 habits for a healthier heart'), findsNothing);
      expect(find.text('Stay Hydrated'), findsNothing);
      expect(find.text('Heart Health'), findsNothing);

      // Clean unmount
      await tester.pumpWidget(const SizedBox());
    });
  });
}
