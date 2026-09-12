import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/auth/profile_completion_service.dart';
import '../../core/auth/role_session_guard.dart';
import '../../core/enums/user_type.dart';
import '../../core/firebase/firestore_screen_sync.dart';
import '../../core/session/lab_session.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/adaptive_app_shell.dart';
import '../../widgets/complete_profile_prompt.dart';
import 'data/lab_connection_store.dart';
import 'data/lab_registry.dart';
import 'data/lab_notification_store.dart';
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

  static const _tabs = [
    (icon: TablerIcons.flask, label: 'Orders'),
    (icon: TablerIcons.user_plus, label: 'Patient'),
    (icon: TablerIcons.search, label: 'Connect'),
    (icon: TablerIcons.bell, label: 'Notifications'),
    (icon: TablerIcons.user, label: 'Profile'),
  ];

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
          LabNotificationStore.instance,
          LabConnectionStore.instance,
        ]),
        builder: (context, _) {
          final labId = LabSession.loggedInLabId;
          final lab = LabRegistry.findById(labId);
          final labName = lab?.labName ?? LabSession.loggedInLabName;
          final displayName = labName.isNotEmpty ? labName : 'Lab';
          final connectPending = labId.isNotEmpty &&
              (LabConnectionStore.instance.pendingForLabFromDoctor(labId).isNotEmpty ||
                  LabConnectionStore.instance.pendingSentByLab(labId).isNotEmpty);
          final requestDots = [false, false, connectPending, false, false];

          return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.biotech_outlined, color: AppColors.labPurple),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Diagnostic Lab',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppColors.textSecondaryOf(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: AdaptiveAppShell(
                showMobileLogout: false,
                selectedIndex: _index,
                onDestinationSelected: _onTabSelected,
                accentColor: AppColors.labPurple,
                requestDots: requestDots,
                destinations: _tabs
                    .map((t) => NavigationDestination(icon: Icon(t.icon), label: t.label))
                    .toList(),
                child: IndexedStack(
                  index: _index,
                  children: [
                    ProfileDataGate(
                      role: UserType.lab,
                      child: const LabOrdersTab(),
                    ),
                    ProfileDataGate(
                      role: UserType.lab,
                      child: const LabWalkInScreen(),
                    ),
                    ProfileDataGate(
                      role: UserType.lab,
                      child: const LabConnectDoctorsScreen(),
                    ),
                    ProfileDataGate(
                      role: UserType.lab,
                      child: const LabNotificationsScreen(),
                    ),
                    const LabProfileScreen(),
                  ],
                ),
              ),
            ),
          ],
          );
        },
      ),
    );
  }
}
