import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/features/patient/home/widgets/home_search_bar.dart';

String? _plainTextOf(Widget widget) {
  if (widget is Text) {
    return widget.data ?? widget.textSpan?.toPlainText();
  }
  if (widget is RichText) {
    return widget.text.toPlainText();
  }
  return null;
}

Finder findAnimatedPlaceholder(String text) => find.byWidgetPredicate(
      (widget) => _plainTextOf(widget) == text,
      description: 'animated placeholder "$text"',
    );

Finder findAnyAnimatedPlaceholder() => find.byWidgetPredicate(
      (widget) => (_plainTextOf(widget) ?? '').startsWith('Search for '),
      description: 'animated placeholder',
    );

void main() {
  group('HomeSearchBar animated rotating placeholder tests', () {
    testWidgets(
        'Renders animated placeholder and transitions through search words',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HomeSearchBar(),
          ),
        ),
      );

      // Initial frame shows the animated placeholder prefix immediately.
      expect(findAnyAnimatedPlaceholder(), findsOneWidget);

      // The typewriter completes the first configured search word.
      await tester.pump(const Duration(milliseconds: 700));
      expect(findAnimatedPlaceholder('Search for Doctors'), findsOneWidget);

      // After the delete/pause/type cycle, the next configured word appears.
      await tester.pump(const Duration(milliseconds: 2700));
      expect(findAnimatedPlaceholder('Search for Labs'), findsOneWidget);

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

      expect(findAnyAnimatedPlaceholder(), findsOneWidget);

      // Tap on TextField to focus
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      await tester.tap(textField);
      await tester.pump();

      // Once focused, overlay should disappear
      expect(findAnyAnimatedPlaceholder(), findsNothing);

      // Enter text
      await tester.enterText(textField, 'Cardiologist');
      await tester.pump();
      expect(findAnyAnimatedPlaceholder(), findsNothing);

      // Clear text
      await tester.enterText(textField, '');
      await tester.pump();

      // Still focused -> overlay still hidden
      expect(findAnyAnimatedPlaceholder(), findsNothing);

      // Unfocus
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      // Unfocused and empty -> overlay reappears
      expect(findAnyAnimatedPlaceholder(), findsOneWidget);

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
