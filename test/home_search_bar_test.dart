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

const _placeholderPrefix = 'Search for ';

Finder findPlaceholderOverlay() => find.descendant(
      of: find.byType(HomeSearchBar),
      matching: find.byType(IgnorePointer),
    );

String placeholderTextOf(WidgetTester tester) {
  final textFinder = find.descendant(
    of: findPlaceholderOverlay(),
    matching: find.byType(Text),
  );
  if (textFinder.evaluate().isNotEmpty) {
    return _plainTextOf(tester.firstWidget<Text>(textFinder))!;
  }

  final richTextFinder = find.descendant(
    of: findPlaceholderOverlay(),
    matching: find.byType(RichText),
  );
  if (richTextFinder.evaluate().isNotEmpty) {
    return _plainTextOf(tester.firstWidget<RichText>(richTextFinder))!;
  }

  throw TestFailure('Could not locate animated placeholder text widget.');
}

void main() {
  group('HomeSearchBar animated rotating placeholder tests', () {
    testWidgets('Renders animated placeholder and advances to the next word',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HomeSearchBar(),
          ),
        ),
      );

      // Initial frame shows the animated placeholder prefix immediately.
      expect(findPlaceholderOverlay(), findsOneWidget);
      expect(placeholderTextOf(tester), startsWith(_placeholderPrefix));

      // After one second, the first word is fully visible and stable.
      await tester.pump(const Duration(seconds: 1));
      expect(placeholderTextOf(tester), 'Search for Doctors');

      // Another 3.5s lands well inside the next word's stable display window.
      await tester.pump(const Duration(milliseconds: 3500));
      expect(placeholderTextOf(tester), 'Search for Labs');

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

      expect(findPlaceholderOverlay(), findsOneWidget);

      // Tap on TextField to focus
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      await tester.tap(textField);
      await tester.pump();

      // Once focused, overlay should disappear
      expect(findPlaceholderOverlay(), findsNothing);

      // Enter text
      await tester.enterText(textField, 'Cardiologist');
      await tester.pump();
      expect(findPlaceholderOverlay(), findsNothing);

      // Clear text
      await tester.enterText(textField, '');
      await tester.pump();

      // Still focused -> overlay still hidden
      expect(findPlaceholderOverlay(), findsNothing);

      // Unfocus
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      // Unfocused and empty -> overlay reappears
      expect(findPlaceholderOverlay(), findsOneWidget);

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
