import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/auth/verification_lifecycle.dart';
import 'package:medibond/core/enums/user_type.dart';
import 'package:medibond/features/lab/screens/lab_dashboard_tabs.dart';
import 'package:medibond/features/shared/widgets/invite_doctor_sheet.dart';
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

  group('InviteDoctorSheet role awareness and styling', () {
    testWidgets(
        'renders pharmacy invite sheet with green accent and lowercase store text',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  InviteDoctorSheet.show(
                    context,
                    partnerRole: UserType.medicalStore,
                    partnerId: 'store-test-99',
                    partnerTypeLabel: 'store',
                    accentColor: const Color(0xFF10B981),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Title
      expect(find.text('Invite Doctor'), findsOneWidget);

      // Body text with lowercase "your store."
      expect(
        find.text(
          'Share this link with a doctor who is not on DoctorNect yet. They can download the app and connect with your store.',
        ),
        findsOneWidget,
      );

      // URL
      expect(
        find.text(
            'https://doctornect.com/download?store=store-test-99&role=doctor'),
        findsOneWidget,
      );

      // Buttons
      expect(find.text('Copy invite'), findsOneWidget);
      expect(find.text('Share invite'), findsOneWidget);

      final filledBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Copy invite'),
      );
      expect(filledBtn.style?.backgroundColor?.resolve({}),
          const Color(0xFF10B981));
    });

    testWidgets(
        'renders lab invite sheet with lab purple accent and lowercase lab text',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  InviteDoctorSheet.show(
                    context,
                    partnerRole: UserType.lab,
                    partnerId: 'lab-test-77',
                    partnerTypeLabel: 'lab',
                    accentColor: const Color(0xFF6366F1),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Title
      expect(find.text('Invite Doctor'), findsOneWidget);

      // Body text with lowercase "your lab."
      expect(
        find.text(
          'Share this link with a doctor who is not on DoctorNect yet. They can download the app and connect with your lab.',
        ),
        findsOneWidget,
      );

      // URL
      expect(
        find.text(
            'https://doctornect.com/download?lab=lab-test-77&role=doctor'),
        findsOneWidget,
      );

      // Buttons
      expect(find.text('Copy invite'), findsOneWidget);
      expect(find.text('Share invite'), findsOneWidget);

      final filledBtn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Copy invite'),
      );
      expect(filledBtn.style?.backgroundColor?.resolve({}),
          const Color(0xFF6366F1));
    });
  });

  group('LabOrderTabSwitcher and LabSearchField theme tests', () {
    testWidgets(
        'renders LabOrderTabSwitcher in dark mode with dark track, white active text, and Done count 0',
        (tester) async {
      final controller = TabController(length: 2, vsync: const TestVSync());

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: LabOrderTabSwitcher(
              controller: controller,
              newCount: 3,
              completedCount: 0,
            ),
          ),
        ),
      );

      // Verify "New" and "Done" tabs are present
      expect(find.text('New'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);

      // Verify count badge shows on both (including 0 on Done)
      expect(find.text('3'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);

      // Active tab (New) label has white text in dark mode
      final newTextWidget = tester.widget<Text>(find.text('New'));
      expect(newTextWidget.style?.color, Colors.white);

      // Inactive tab (Done) label has secondary text color in dark mode
      final doneTextWidget = tester.widget<Text>(find.text('Done'));
      expect(doneTextWidget.style?.color, const Color(0xFF94A3B8));

      // Tap Done tab
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(controller.index, 1);

      // Now Done is active with white text
      final doneActiveText = tester.widget<Text>(find.text('Done'));
      expect(doneActiveText.style?.color, Colors.white);
    });

    testWidgets(
        'renders LabOrderTabSwitcher in light mode with purple active text',
        (tester) async {
      final controller = TabController(length: 2, vsync: const TestVSync());

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
            body: LabOrderTabSwitcher(
              controller: controller,
              newCount: 2,
              completedCount: 5,
            ),
          ),
        ),
      );

      // Active tab (New) label has purple accent text in light mode
      final newTextWidget = tester.widget<Text>(find.text('New'));
      expect(newTextWidget.style?.color, const Color(0xFF6366F1));

      // Both count badges visible
      expect(find.text('2'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('renders LabSearchField with dark border in dark mode',
        (tester) async {
      final controller = TextEditingController();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: LabSearchField(
              controller: controller,
              onChanged: () {},
            ),
          ),
        ),
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      final inputDec = textField.decoration;
      final border = inputDec?.border as OutlineInputBorder?;
      expect(border?.borderSide.color, const Color(0xFF334155));
    });
  });
}
