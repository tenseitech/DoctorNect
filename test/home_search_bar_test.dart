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

Finder _placeholderTextFinder({required bool richText}) => find.descendant(
      of: find.byType(HomeSearchBar),
      matching: find.byWidgetPredicate(
        (widget) {
          if (richText && widget is! RichText) return false;
          if (!richText && widget is! Text) return false;
          return (_plainTextOf(widget) ?? '').startsWith(_placeholderPrefix);
        },
        description: richText ? 'placeholder rich text' : 'placeholder text',
      ),
    );

bool hasPlaceholderText(WidgetTester tester) {
  return _placeholderTextFinder(richText: false).evaluate().isNotEmpty ||
      _placeholderTextFinder(richText: true).evaluate().isNotEmpty;
}

String placeholderTextOf(WidgetTester tester) {
  final textFinder = _placeholderTextFinder(richText: false);
  if (textFinder.evaluate().isNotEmpty) {
    return _plainTextOf(tester.firstWidget<Text>(textFinder))!;
  }

  final richTextFinder = _placeholderTextFinder(richText: true);
  if (richTextFinder.evaluate().isNotEmpty) {
    return _plainTextOf(tester.firstWidget<RichText>(richTextFinder))!;
  }

  throw TestFailure('Could not locate animated placeholder text widget.');
}

Future<void> pumpUntilPlaceholder(
  WidgetTester tester, {
  required bool Function(String text) matches,
  required String failureMessage,
  Duration step = const Duration(milliseconds: 50),
  Duration timeout = const Duration(seconds: 3),
}) async {
  final attempts = timeout.inMilliseconds ~/ step.inMilliseconds;

  for (var i = 0; i <= attempts; i++) {
    final text = placeholderTextOf(tester);
    if (matches(text)) return;
    await tester.pump(step);
  }

  throw TestFailure(
    '$failureMessage Last rendered value was "${placeholderTextOf(tester)}".',
  );
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
      expect(hasPlaceholderText(tester), isTrue);
      expect(placeholderTextOf(tester), startsWith(_placeholderPrefix));

      // After one second, the first word is fully visible and stable.
      await tester.pump(const Duration(seconds: 1));
      expect(placeholderTextOf(tester), 'Search for Doctors');

      await pumpUntilPlaceholder(
        tester,
        matches: (text) => text != 'Search for Doctors',
        failureMessage: 'Placeholder never advanced away from Doctors.',
        timeout: const Duration(seconds: 2),
      );

      // Only allow enough time for the immediate next completed word to appear.
      await pumpUntilPlaceholder(
        tester,
        matches: (text) => text == 'Search for Labs',
        failureMessage: 'Placeholder never settled on Labs.',
        timeout: const Duration(milliseconds: 1500),
      );
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

      expect(hasPlaceholderText(tester), isTrue);

      // Tap on TextField to focus
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      await tester.tap(textField);
      await tester.pump();

      // Once focused, overlay should disappear
      expect(hasPlaceholderText(tester), isFalse);

      // Enter text
      await tester.enterText(textField, 'Cardiologist');
      await tester.pump();
      expect(hasPlaceholderText(tester), isFalse);

      // Clear text
      await tester.enterText(textField, '');
      await tester.pump();

      // Still focused -> overlay still hidden
      expect(hasPlaceholderText(tester), isFalse);

      // Unfocus
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      // Unfocused and empty -> overlay reappears
      expect(hasPlaceholderText(tester), isTrue);

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
