import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/theme/app_colors.dart';
import 'package:medibond/core/theme/app_theme.dart';
import 'package:medibond/widgets/adaptive_app_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Doctor shell floating taskbar tests', () {
    const destinations = [
      NavigationDestination(
        icon: Icon(Icons.home_outlined, size: 22),
        selectedIcon: Icon(Icons.home_rounded, size: 22),
        label: 'Home',
      ),
      NavigationDestination(
        icon: Icon(TablerIcons.users, size: 22),
        selectedIcon: Icon(TablerIcons.users, size: 22),
        label: 'Patients',
      ),
      NavigationDestination(
        icon: Icon(TablerIcons.calendar, size: 22),
        selectedIcon: Icon(TablerIcons.calendar_filled, size: 22),
        label: 'Appointments',
      ),
      NavigationDestination(
        icon: Icon(TablerIcons.pill, size: 22),
        selectedIcon: Icon(TablerIcons.pill_filled, size: 22),
        label: 'Medical Store',
      ),
      NavigationDestination(
        icon: Icon(TablerIcons.flask, size: 22),
        selectedIcon: Icon(TablerIcons.flask_filled, size: 22),
        label: 'Labs',
      ),
    ];

    test('Destinations use stroke vector icons, no Image.asset', () {
      for (final dest in destinations) {
        expect(dest.icon, isA<Icon>());
        expect(dest.selectedIcon, isA<Icon>());
      }
    });

    testWidgets('Renders floating glassmorphic taskbar on mobile',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      var selectedIndex = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(AppColors.doctorBlue),
          home: StatefulBuilder(
            builder: (context, setState) {
              return AdaptiveAppShell(
                selectedIndex: selectedIndex,
                onDestinationSelected: (index) {
                  setState(() => selectedIndex = index);
                },
                accentColor: AppColors.doctorBlue,
                filledActiveTabs: false,
                showMobileTopBar: false,
                destinations: destinations,
                glassmorphic: true,
                child: Center(child: Text('Tab: $selectedIndex')),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check that BackdropFilter is present for the blur effect
      expect(find.byType(BackdropFilter), findsOneWidget);
      final backdrop =
          tester.widget<BackdropFilter>(find.byType(BackdropFilter));
      expect(backdrop.filter, isNotNull);

      // Verify all 5 tab labels are visible
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Patients'), findsOneWidget);
      expect(find.text('Appointment'), findsOneWidget); // compact label
      expect(find.text('Medical\nStore'), findsOneWidget); // compact label
      expect(find.text('Labs'), findsOneWidget);

      // Verify tapping a tab switches the index
      await tester.tap(find.text('Patients'));
      await tester.pumpAndSettle();
      expect(find.text('Tab: 1'), findsOneWidget);

      await tester.tap(find.text('Labs'));
      await tester.pumpAndSettle();
      expect(find.text('Tab: 4'), findsOneWidget);
    });
  });
}
