import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/auth/verification_lifecycle.dart';
import 'package:medibond/widgets/verified_badge_icon.dart';
import 'package:medibond/widgets/multi_tag_input_field.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VerifiedBadgeIcon', () {
    testWidgets('renders green verified icon with DoctorNect tooltip',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: VerifiedBadgeIcon(),
            ),
          ),
        ),
      );

      final iconFinder = find.byIcon(Icons.verified);
      expect(iconFinder, findsOneWidget);

      final iconWidget = tester.widget<Icon>(iconFinder);
      expect(iconWidget.color, const Color(0xFF16A34A));

      final tooltipFinder = find.byType(Tooltip);
      expect(tooltipFinder, findsOneWidget);

      final tooltipWidget = tester.widget<Tooltip>(tooltipFinder);
      expect(tooltipWidget.message, 'Verified by DoctorNect');
    });

    testWidgets('supports custom size and color', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: VerifiedBadgeIcon(
                size: 24,
                color: Colors.white,
              ),
            ),
          ),
        ),
      );

      final iconWidget = tester.widget<Icon>(find.byIcon(Icons.verified));
      expect(iconWidget.size, 24);
      expect(iconWidget.color, Colors.white);
    });
  });

  group('VerificationStage mapping', () {
    test('correctly parses verified, submitted, and rejected stages', () {
      expect(
          VerificationStage.fromString('verified'), VerificationStage.verified);
      expect(
          VerificationStage.fromString('approved'), VerificationStage.verified);
      expect(VerificationStage.fromString('submitted_for_verification'),
          VerificationStage.submittedForVerification);
      expect(VerificationStage.fromString('pending_review'),
          VerificationStage.submittedForVerification);
      expect(
          VerificationStage.fromString('rejected'), VerificationStage.rejected);
      expect(VerificationStage.fromString('revision_requested'),
          VerificationStage.revisionRequested);
      expect(VerificationStage.fromString('unknown'),
          VerificationStage.registered);
    });
  });

  group('MultiTagInputField with showAddButton toggle', () {
    testWidgets(
        'hides Add button when showAddButton is false and adds tag via onFieldSubmitted',
        (tester) async {
      final List<String> tags = [];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return MultiTagInputField(
                  tags: tags,
                  onAdd: (newTag) {
                    setState(() => tags.add(newTag));
                  },
                  onRemove: (tag) {
                    setState(() => tags.remove(tag));
                  },
                  showAddButton: false,
                  suggestionFetcher: (q) => ['CBC', 'Lipid profile'],
                );
              },
            ),
          ),
        ),
      );

      // Verify Add button is NOT present
      expect(find.text('Add'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);

      // Verify text field exists and can be typed into
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);

      await tester.enterText(textField, 'Thyroid profile');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(tags, contains('Thyroid profile'));
      expect(find.text('Thyroid profile'), findsOneWidget);
    });

    testWidgets('shows Add button when showAddButton is true', (tester) async {
      final List<String> tags = [];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MultiTagInputField(
              tags: tags,
              onAdd: (tag) => tags.add(tag),
              onRemove: (tag) => tags.remove(tag),
              showAddButton: true,
              addButtonLabel: 'Add test',
            ),
          ),
        ),
      );

      expect(find.text('Add test'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });
  });

  group('Lab orders count date-scoping logic', () {
    bool isSameDay(DateTime a, DateTime b) {
      return a.year == b.year && a.month == b.month && a.day == b.day;
    }

    test('counts only active orders created today', () {
      final today = DateTime(2026, 9, 30, 10, 0);
      final yesterday = DateTime(2026, 9, 29, 14, 0);

      final orders = [
        {'id': '1', 'status': 'new', 'createdAt': today},
        {'id': '2', 'status': 'in_progress', 'createdAt': today},
        {'id': '3', 'status': 'completed', 'createdAt': today},
        {'id': '4', 'status': 'declined', 'createdAt': today},
        {'id': '5', 'status': 'new', 'createdAt': yesterday},
        {'id': '6', 'status': 'in_progress', 'createdAt': yesterday},
        {'id': '7', 'status': 'sample_collected', 'createdAt': yesterday},
        {'id': '8', 'status': 'processing', 'createdAt': yesterday},
      ];

      // Historical unscoped count sums all active (status != completed && status != declined) = 6
      final unscopedActiveCount = orders
          .where((o) => o['status'] != 'completed' && o['status'] != 'declined')
          .length;
      expect(unscopedActiveCount, 6);

      // Scoped count matches today's tab view
      final todayActiveCount = orders.where((o) {
        final status = o['status'] as String;
        final createdAt = o['createdAt'] as DateTime;
        final isActive = status != 'completed' && status != 'declined';
        return isActive && isSameDay(createdAt, today);
      }).length;

      expect(todayActiveCount, 2);
    });
  });
}
