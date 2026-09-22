import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/features/patient/home/widgets/home_search_bar.dart';

void main() {
  group('HomeSearchBar animated rotating placeholder tests', () {
    testWidgets(
        'Renders initial placeholder and transitions through loop every 2.5s',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HomeSearchBar(),
          ),
        ),
      );

      // Initial frame: "Search for doctor" must be visible
      expect(find.text('Search for doctor'), findsOneWidget);

      // Advance by 2.5s -> transitions to "Search for lab"
      await tester.pump(const Duration(milliseconds: 2500));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Search for lab'), findsOneWidget);

      // Advance by 2.5s -> transitions to "Search for language or location"
      await tester.pump(const Duration(milliseconds: 2500));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Search for language or location'), findsOneWidget);

      // Advance by 2.5s -> transitions to "Search for ambulance"
      await tester.pump(const Duration(milliseconds: 2500));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Search for ambulance'), findsOneWidget);

      // Advance by 2.5s -> loops back to "Search for doctor"
      await tester.pump(const Duration(milliseconds: 2500));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Search for doctor'), findsOneWidget);

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

      expect(find.text('Search for doctor'), findsOneWidget);

      // Tap on TextField to focus
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      await tester.tap(textField);
      await tester.pump();

      // Once focused, overlay should disappear
      expect(find.text('Search for doctor'), findsNothing);

      // Enter text
      await tester.enterText(textField, 'Cardiologist');
      await tester.pump();
      expect(find.text('Search for doctor'), findsNothing);

      // Clear text
      await tester.enterText(textField, '');
      await tester.pump();

      // Still focused -> overlay still hidden
      expect(find.text('Search for doctor'), findsNothing);

      // Unfocus
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      // Unfocused and empty -> overlay reappears
      expect(find.text('Search for doctor'), findsOneWidget);

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
