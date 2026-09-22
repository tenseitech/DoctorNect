import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/theme/app_colors.dart';
import 'package:medibond/core/theme/app_theme.dart';
import 'package:medibond/features/patient/home/widgets/explore_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExploreSection Mobile Scroll Hint & 3.5 Columns Grid Tests', () {
    testWidgets(
        'Mobile view renders horizontal 2-row grid with item width sized for ~3.5 columns',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: ExploreSection(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Section title and View all button should be visible
      expect(find.text('Specialities'), findsOneWidget);
      expect(find.text('View all'), findsOneWidget);

      // Verify horizontal GridView exists
      final gridFinder = find.byType(GridView);
      expect(gridFinder, findsOneWidget);

      final gridView = tester.widget<GridView>(gridFinder);
      expect(gridView.scrollDirection, Axis.horizontal);

      final gridDelegate =
          gridView.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
      expect(gridDelegate.crossAxisCount, 2);

      // Expected itemWidth for 390 width: (390 - 16 - 30) / 3.5 = 344 / 3.5 = 98.28px
      expect(gridDelegate.mainAxisExtent, closeTo(98.28, 0.5));
    });

    testWidgets(
        'Mobile view contains right-edge fade gradient inside IgnorePointer',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

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
      await tester.pumpAndSettle();

      // Find IgnorePointer that wraps AnimatedOpacity for fade gradient
      final ignorePointerFinder = find.descendant(
        of: find.byType(ExploreSection),
        matching: find.byType(IgnorePointer),
      );
      expect(ignorePointerFinder, findsWidgets);

      // Verify gradient has Transparent to Scaffold background color
      final animatedOpacityFinder = find.descendant(
        of: ignorePointerFinder,
        matching: find.byType(AnimatedOpacity),
      );
      expect(animatedOpacityFinder, findsOneWidget);

      final animatedOpacity =
          tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      // At start (offset 0), canScrollRight is true, so opacity is 1.0
      expect(animatedOpacity.opacity, 1.0);
    });

    testWidgets(
        'Fade gradient hides when scrolled to the end of the specialities list',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: ExploreSection(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollableFinder = find.descendant(
        of: find.byType(ExploreSection),
        matching: find.byType(Scrollable),
      );
      expect(scrollableFinder, findsWidgets);

      // Scroll horizontal grid completely to the right end
      final horizontalScrollable = scrollableFinder.first;
      await tester.drag(horizontalScrollable, const Offset(-3000, 0));
      await tester.pumpAndSettle();

      // Fade gradient should now be faded out (opacity 0.0)
      final animatedOpacityFinder = find.descendant(
        of: find.byType(IgnorePointer),
        matching: find.byType(AnimatedOpacity),
      );
      final animatedOpacity =
          tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(animatedOpacity.opacity, 0.0);
    });

    testWidgets(
        'Web layout displays wide grid without horizontal scrolling or mobile gradient',
        (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: ExploreSection(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Title should be visible
      expect(find.text('Specialities'), findsOneWidget);
      // 'View all' button is hidden on web as all items are shown
      expect(find.text('View all'), findsNothing);

      // GridView is vertical in wide mode
      final gridFinder = find.byType(GridView);
      expect(gridFinder, findsOneWidget);
      final gridView = tester.widget<GridView>(gridFinder);
      expect(gridView.scrollDirection, Axis.vertical);

      // No fade gradient in web layout
      final animatedOpacityUnderExplore = find.descendant(
        of: find.byType(ExploreSection),
        matching: find.byType(AnimatedOpacity),
      );
      expect(animatedOpacityUnderExplore, findsNothing);
    });
  });
}
