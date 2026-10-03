import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/core/enums/user_type.dart';
import 'package:medibond/core/theme/app_colors.dart';
import 'package:medibond/core/theme/app_theme.dart';
import 'package:medibond/features/doctor/patients/doctor_patients_screen.dart';
import 'package:medibond/features/doctor/shared/doctor_connected_partners_base_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Priority 1 Doctor UI/UX Bug Fixes Tests', () {
    testWidgets(
      '1. Patients screen: FAB is positioned at bottom 96 on mobile and list has 180 bottom padding with AlwaysScrollableScrollPhysics',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(AppColors.doctorBlue),
            home: const Scaffold(body: DoctorPatientsScreen()),
          ),
        );
        await tester.pumpAndSettle();

        // Check FAB position
        final positionedFabFinder = find.ancestor(
          of: find.byType(FloatingActionButton),
          matching: find.byType(Positioned),
        );
        expect(positionedFabFinder, findsOneWidget);
        final Positioned fabPositioned = tester.widget(positionedFabFinder);
        expect(fabPositioned.bottom, 96.0);
        expect(fabPositioned.right, 16.0);

        // Check ListView scroll padding and physics
        final listViewFinder = find.byType(ListView);
        if (listViewFinder.evaluate().isNotEmpty) {
          final ListView listView = tester.widget(listViewFinder);
          expect(listView.physics, isA<AlwaysScrollableScrollPhysics>());
          final EdgeInsets padding = listView.padding as EdgeInsets;
          expect(padding.bottom, 180.0);
        }
      },
    );

    testWidgets(
      '2. Medical Store and Diagnostic Labs: Disconnect opens confirmation dialog with exact safety prompt',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        var disconnectedId = '';
        var disconnectedName = '';

        final testConnection = DoctorPartnerConnectionItem(
          id: 'conn-123',
          partnerId: 'pharmacy-1',
          partnerName: 'Apollo Pharmacy',
          requestedAt: DateTime.now(),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(AppColors.doctorBlue),
            home: Scaffold(
              body: DoctorConnectedPartnersBaseView(
                partnerRole: UserType.medicalStore,
                partnerHeaderTitle: 'Pharmacy',
                partnerHeaderSubtitle: 'Connected stores',
                partnerTypeLabel: 'Medical Store',
                accentColor: AppColors.doctorBlue,
                listenables: const [],
                activeConnections: () => [testConnection],
                pendingFromPartner: () => [],
                pendingFromDoctor: () => [],
                searchResults: () => [],
                searchHintText: 'Search stores...',
                cityFilterLabel: () => null,
                activitySubtitleBuilder: (_) => 'Active',
                onSearchPartners: (_) {},
                onViewPatients: (_, __) {},
                onDisconnect: (id, name) {
                  disconnectedId = id;
                  disconnectedName = name;
                },
                onApprove: (_, __) {},
                onReject: (_, __) {},
                onRevoke: (_, __) {},
                onSendRequest: (_) => null,
                onOpenAddPartner: () {},
                onOpenInviteSheet: () {},
                attachFirestoreSync: () {},
                detachFirestoreSync: () {},
                isConnected: (_) => true,
                isPendingSent: (_) => false,
                isPendingFromPartner: (_) => false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Find disconnect button (link_off icon)
        final disconnectButton = find.byIcon(Icons.link_off);
        expect(disconnectButton, findsOneWidget);

        // Tap disconnect icon
        await tester.tap(disconnectButton);
        await tester.pumpAndSettle();

        // Verify confirmation dialog title and content
        expect(find.text('Disconnect Apollo Pharmacy?'), findsOneWidget);
        expect(
          find.text('Disconnect Apollo Pharmacy? This cannot be undone.'),
          findsOneWidget,
        );

        // Disconnect not yet executed
        expect(disconnectedId, isEmpty);

        // Tap Cancel first
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(disconnectedId, isEmpty);

        // Tap Disconnect button again
        await tester.tap(disconnectButton);
        await tester.pumpAndSettle();

        // Tap 'Disconnect' confirmation button in dialog
        final dialogDisconnectAction = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Disconnect'),
        );
        expect(dialogDisconnectAction, findsOneWidget);
        await tester.tap(dialogDisconnectAction);
        await tester.pumpAndSettle();

        // Now verify disconnect executed with correct arguments
        expect(disconnectedId, 'conn-123');
        expect(disconnectedName, 'Apollo Pharmacy');
      },
    );
  });
}
