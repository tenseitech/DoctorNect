import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/accessibility/accessibility_tokens.dart';
import 'package:medibond/widgets/accessible_icon_button.dart';

void main() {
  testWidgets('AccessibleIconButton.back exposes semantics and 48dp target',
      (tester) async {
    var tapped = false;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AccessibleIconButton.back(
          onPressed: () => tapped = true,
        ),
      ),
    ),
  );

  expect(find.bySemanticsLabel('Go back'), findsOneWidget);
  final button = tester.widget<IconButton>(find.byType(IconButton));
  expect(
    button.constraints?.minWidth,
    AccessibilityTokens.minTapTarget,
  );

  await tester.tap(find.byType(IconButton));
  await tester.pump();
  expect(tapped, isTrue);
});
}