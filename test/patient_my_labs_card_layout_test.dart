import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/theme/app_colors.dart';
import 'package:medibond/core/theme/app_theme.dart';
import 'package:medibond/features/patient/data/patient_favorites_store.dart';
import 'package:medibond/features/patient/lab/my_labs_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testLab = SavedLabEntry(
    id: 'lab-1',
    name: 'KD Labs',
    rating: 4.5,
    area: 'India, Nagpur, Maharashtra',
  );

  group('My Labs Card Layout Tests', () {
    testWidgets(
        'Compact / mobile screen renders 2-part stacked layout with equal-width buttons',
        (tester) async {
      // Set mobile phone dimensions (360 width)
      tester.view.physicalSize = const Size(360, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Clear and populate favorites store with test lab
      PatientFavoritesStore.instance.clear();
      await PatientFavoritesStore.instance.addLab(testLab);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.patientTeal),
          home: const MyLabsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Find lab title and address
      final nameFinder = find.text('KD Labs');
      final areaFinder = find.text('India, Nagpur, Maharashtra');
      expect(nameFinder, findsOneWidget);
      expect(areaFinder, findsOneWidget);

      final areaText = tester.widget<Text>(areaFinder);
      expect(areaText.maxLines, 2);
      expect(areaText.overflow, TextOverflow.ellipsis);

      // Find Remove and Book buttons
      final removeBtnFinder = find.widgetWithText(FilledButton, 'Remove');
      final bookBtnFinder = find.widgetWithText(FilledButton, 'Book');
      expect(removeBtnFinder, findsOneWidget);
      expect(bookBtnFinder, findsOneWidget);

      final removeBtn = tester.widget<FilledButton>(removeBtnFinder);
      final bookBtn = tester.widget<FilledButton>(bookBtnFinder);

      // Both buttons have height >= 40px
      final removeSize = tester.getSize(removeBtnFinder);
      final bookSize = tester.getSize(bookBtnFinder);
      expect(removeSize.height, closeTo(40.0, 1.0));
      expect(bookSize.height, closeTo(40.0, 1.0));

      // In compact mode, both buttons are Expanded in bottom row, so their widths are equal
      expect(removeSize.width, closeTo(bookSize.width, 1.0));

      // Check button colors
      expect(removeBtn.style?.backgroundColor?.resolve({}), AppColors.error);
      expect(bookBtn.style?.backgroundColor?.resolve({}), AppColors.labPurple);

      // Buttons are stacked vertically below the lab text
      final nameBottom = tester.getBottomLeft(nameFinder).dy;
      final removeTop = tester.getTopLeft(removeBtnFinder).dy;
      expect(removeTop, greaterThan(nameBottom));

      // Clean unmount
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'Wide / web screen renders single-row layout with min-size buttons',
        (tester) async {
      // Set desktop / web dimensions
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      PatientFavoritesStore.instance.clear();
      await PatientFavoritesStore.instance.addLab(testLab);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(AppColors.patientTeal),
          home: const MyLabsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final removeBtnFinder = find.widgetWithText(FilledButton, 'Remove');
      final bookBtnFinder = find.widgetWithText(FilledButton, 'Book');
      expect(removeBtnFinder, findsOneWidget);
      expect(bookBtnFinder, findsOneWidget);

      // Check button sizes
      final removeSize = tester.getSize(removeBtnFinder);
      final bookSize = tester.getSize(bookBtnFinder);
      expect(removeSize.height, closeTo(40.0, 1.0));
      expect(bookSize.height, closeTo(40.0, 1.0));

      // In single-row layout, buttons are horizontally aligned with lab name
      final nameTop = tester.getTopLeft(find.text('KD Labs')).dy;
      final removeTop = tester.getTopLeft(removeBtnFinder).dy;
      // In single row, they share the same card row area (within ~20px tolerance)
      expect((removeTop - nameTop).abs(), lessThan(30.0));

      // Distance between Remove and Book button
      final removeRight = tester.getTopRight(removeBtnFinder).dx;
      final bookLeft = tester.getTopLeft(bookBtnFinder).dx;
      expect(bookLeft - removeRight, closeTo(10.0, 1.0));

      // Clean unmount
      await tester.pumpWidget(const SizedBox());
    });
  });
}
