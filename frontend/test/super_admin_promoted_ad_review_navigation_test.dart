import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/admin/super_admin_verification_service.dart';
import 'package:medibond/core/enums/user_type.dart';
import 'package:medibond/features/admin/promoted_ad_review_screen.dart';
import 'package:medibond/features/admin/super_admin_verification_screen.dart';
import 'package:medibond/features/dashboard/dashboard_shell.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SuperAdminVerificationService.debugApplicantsStreamOverride =
        Stream.value([]);
  });

  tearDown(() {
    SuperAdminVerificationService.debugApplicantsStreamOverride = null;
  });

  group('Super Admin Promoted Ad Review Navigation Tests (H-3)', () {
    testWidgets(
        'Super admin verification screen displays review action card and navigates to PromotedAdReviewScreen',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SuperAdminVerificationScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Confirm both the action card and the AppBar icon button exist
      expect(find.byKey(const Key('promoted_ads_review_action_card')),
          findsOneWidget);
      expect(find.text('Promoted Ads Review'), findsOneWidget);
      expect(find.byTooltip('Review promoted ads'), findsOneWidget);

      // Tap on the action card
      await tester.tap(find.byKey(const Key('promoted_ads_review_action_card')));
      await tester.pumpAndSettle();

      // Confirm navigation pushed PromotedAdReviewScreen
      expect(find.byType(PromotedAdReviewScreen), findsOneWidget);
      expect(find.text('Promoted ads'), findsOneWidget);
    });

    testWidgets(
        'AppBar icon button also navigates to PromotedAdReviewScreen',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: SuperAdminVerificationScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the AppBar action button
      await tester.tap(find.byTooltip('Review promoted ads'));
      await tester.pumpAndSettle();

      // Confirm navigation pushed PromotedAdReviewScreen
      expect(find.byType(PromotedAdReviewScreen), findsOneWidget);
      expect(find.text('Promoted ads'), findsOneWidget);
    });

    testWidgets(
        'DashboardShell renders SuperAdminVerificationScreen only for superAdmin role',
        (tester) async {
      // 1. Super Admin role
      await tester.pumpWidget(
        const MaterialApp(
          home: DashboardShell(userType: UserType.superAdmin),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SuperAdminVerificationScreen), findsOneWidget);
      expect(find.text('Promoted Ads Review'), findsOneWidget);
    });
  });
}
