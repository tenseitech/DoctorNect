import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/features/patient/home/widgets/home_search_bar.dart';

void main() {
  group('HomeSearchBar animated rotating placeholder tests', () {
    testWidgets(
        'Renders initial placeholder and transitions through typewriter loop',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HomeSearchBar(),
          ),
        ),
      );

      // Initial frame: "Search for " prefix must be visible
      expect(find.textContaining('Search for'), findsOneWidget);

      // Advance through typing "Doctors" (7 chars * 90ms = 630ms)
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.textContaining('Doctors'), findsOneWidget);

      // Advance through pause + backspacing + pause + typing "Labs"
      // Pause 1800ms + 7*45ms (315ms) + 250ms + 4*90ms (360ms) = ~2800ms
      await tester.pump(const Duration(milliseconds: 3000));
      expect(find.textContaining('Labs'), findsOneWidget);

      // Dispose widget cleanly
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('Focusing or typing hides the placeholder overlay',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HomeSearchBar(),
          ),
        ),
      );

      expect(find.textContaining('Search for'), findsOneWidget);

      // Tap on TextField to focus
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      await tester.tap(textField);
      await tester.pump();

      // Once focused, overlay should disappear
      expect(find.textContaining('Search for'), findsNothing);

      // Enter text
      await tester.enterText(textField, 'Cardiologist');
      await tester.pump();
      expect(find.textContaining('Search for'), findsNothing);

      // Clear text
      await tester.enterText(textField, '');
      await tester.pump();

      // Still focused -> overlay still hidden
      expect(find.textContaining('Search for'), findsNothing);

      // Unfocus
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      // Unfocused and empty -> overlay reappears
      expect(find.textContaining('Search for'), findsOneWidget);

      // Dispose widget cleanly
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('Search button submits query or triggers callback',
        (tester) async {
      String submittedQuery = '';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeSearchBar(
              onSubmitted: (q) => submittedQuery = q,
            ),
          ),
        ),
      );

      final textField = find.byType(TextField);
      await tester.enterText(textField, 'Dentist');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();

      expect(submittedQuery, 'Dentist');

      // Dispose widget cleanly
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
