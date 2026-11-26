import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/widgets/shell/role_empty_state.dart';

void main() {
  testWidgets('RoleEmptyState announces title and subtitle to accessibility',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RoleEmptyState(
            icon: Icons.inbox_outlined,
            title: 'No orders yet',
            subtitle: 'New pharmacy orders will appear here.',
          ),
        ),
      ),
    );

    expect(find.text('No orders yet'), findsOneWidget);
    expect(
      find.text('New pharmacy orders will appear here.'),
      findsOneWidget,
    );
    expect(find.byType(Semantics), findsWidgets);
  });
}