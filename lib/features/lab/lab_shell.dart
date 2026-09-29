import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../core/auth/profile_completion_service.dart';
import '../../core/auth/role_session_guard.dart';
import '../../core/enums/user_type.dart';
import '../../core/firebase/firestore_screen_sync.dart';
import '../../core/session/lab_session.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/complete_profile_prompt.dart';
import '../../widgets/shell/role_shell.dart';
import 'data/lab_connection_store.dart';
import 'data/lab_notification_store.dart';
import 'data/lab_registry.dart';
import 'data/lab_worklist_store.dart';
import 'screens/lab_connect_doctors_screen.dart';
import 'screens/lab_dashboard_tabs.dart';
import 'screens/lab_notifications_screen.dart';
import 'screens/lab_profile_screen.dart';
import 'screens/lab_walkin_screen.dart';

class LabShell extends StatefulWidget {
  const LabShell({super.key});

  @override
  State<LabShell> createState() => _LabShellState();
}

class _LabShellState extends State<LabShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      RoleSessionGuard.verifyRole(context, UserType.lab);
      if (ProfileCompletionService.instance.isComplete) {
        unawaited(LabRegistry.refreshFromFirestore());
      }
      _syncForTab(_index);
    });
  }

  @override
  void dispose() {
    FirestoreScreenSync.detachLabWorklist();
    FirestoreScreenSync.detachLabPendingConnections();
    super.dispose();
  }

  void _onTabSelected(int index) {
    setState(() => _index = index);
    _syncForTab(index);
  }

  void _syncForTab(int index) {
    if (!ProfileCompletionService.instance.isComplete) return;
    final labId = LabSession.loggedInLabId;
    if (labId.isEmpty) return;

    if (index == 4) {
      FirestoreScreenSync.detachLabWorklist();
      FirestoreScreenSync.detachLabPendingConnections();
      return;
    }

    if (index == 0 || index == 1) {
      FirestoreScreenSync.attachLabWorklist(labId);
    } else {
      FirestoreScreenSync.detachLabWorklist();
    }

    FirestoreScreenSync.attachLabPendingConnections(
      role: UserType.lab,
      profileId: labId,
    );
    unawaited(
      LabConnectionStore.instance.refreshActiveConnections(
        role: UserType.lab,
        profileId: labId,
        preferCache: true,
      ),
    );
  }

  int _ordersBadgeCount(String labId) {
    // If not verified, prevent badge leakage on gated operational tab
    if (!ProfileCompletionService.instance.isComplete) return 0;
    final orders = LabWorklistStore.instance.orders;
    final bookings = LabWorklistStore.instance.bookings;
    final newOrders = orders
        .where(
          (o) =>
              (labId.isEmpty || o.labId == labId) &&
              o.status != 'completed' &&
              o.status != 'declined',
        )
        .length;
    final newBookings = bookings
        .where(
          (b) =>
              (labId.isEmpty || b.labId == labId) &&
              b.status != 'completed' &&
              b.status != 'cancelled',
        )
        .length;
    return newOrders + newBookings;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labTheme = isDark
        ? AppTheme.dark(AppColors.labPurple)
        : AppTheme.light(AppColors.labPurple);

    return Theme(
      data: labTheme,
      child: ListenableBuilder(
        listenable: Listenable.merge([
          LabRegistry.instance,
          LabWorklistStore.instance,
          LabNotificationStore.instance,
          LabConnectionStore.instance,
          ProfileCompletionService.instance,
        ]),
        builder: (context, _) {
          final labId = LabSession.loggedInLabId;
          final lab = LabRegistry.findById(labId);
          final labName = lab?.labName ?? LabSession.loggedInLabName;
          final displayName = labName.isNotEmpty ? labName : 'KD Labs';

          final ordersBadge = _ordersBadgeCount(labId);
          final unreadAlerts = LabNotificationStore.instance.unreadCountForLab(
            labId,
          );
          final connectPending =
              labId.isNotEmpty &&
              (LabConnectionStore.instance
                      .pendingForLabFromDoctor(labId)
                      .isNotEmpty ||
                  LabConnectionStore.instance
                      .pendingSentByLab(labId)
                      .isNotEmpty);

          final navItems = [
            RoleNavItem(
              icon: TablerIcons.flask,
              selectedIcon: TablerIcons.flask,
              label: 'Orders',
              mobileLabel: 'Orders',
              badgeCount: ordersBadge > 0 ? ordersBadge : null,
            ),
            const RoleNavItem(
              icon: TablerIcons.user_plus,
              selectedIcon: TablerIcons.user_plus,
              label: 'Walk-in',
              mobileLabel: 'Walk-in',
            ),
            RoleNavItem(
              icon: TablerIcons.link,
              selectedIcon: TablerIcons.link,
              label: 'Connect',
              mobileLabel: 'Connect',
              showDotBadge: connectPending,
            ),
            RoleNavItem(
              icon: TablerIcons.bell,
              selectedIcon: TablerIcons.bell_filled,
              label: 'Notifications',
              mobileLabel: 'Alerts',
              badgeCount: unreadAlerts > 0 ? unreadAlerts : null,
            ),
            const RoleNavItem(
              icon: TablerIcons.user,
              selectedIcon: TablerIcons.user_filled,
              label: 'Profile',
              mobileLabel: 'Profile',
            ),
          ];

          return RoleShell(
            selectedIndex: _index,
            onDestinationSelected: _onTabSelected,
            roleTitle: 'Diagnostic Lab',
            entityName: displayName,
            entityIcon: TablerIcons.flask,
            accentColor: AppColors.labPurple,
            accentGradientEnd: const Color(0xFF7C3AED),
            sidebarWidth: 268.0,
            navItems: navItems,
            child: IndexedStack(
              index: _index,
              children: [
                ProfileDataGate(
                  role: UserType.lab,
                  child: const LabOrdersTab(),
                ),
                const LabWalkInScreen(),
                const LabConnectDoctorsScreen(),
                const LabNotificationsScreen(),
                const LabProfileScreen(),
              ],
            ),
          );
        },
      ),
    );
  }
}
