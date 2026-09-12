import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/auth/profile_completion_service.dart';
import '../../core/auth/role_session_guard.dart';
import '../../core/enums/user_type.dart';
import '../../core/firebase/firestore_screen_sync.dart';
import '../../core/session/medical_store_session.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import 'data/pharmacy_connection_store.dart';
import 'data/medical_store_registry.dart';
import 'data/pharmacy_notification_store.dart';
import 'data/pharmacy_prescription_store.dart';
import 'models/pharmacy_models.dart';
import 'screens/connect_doctors_screen.dart';
import 'screens/store_dashboard_screen.dart';
import 'screens/store_notifications_screen.dart';
import 'screens/store_profile_screen.dart';
import '../../widgets/complete_profile_prompt.dart';
import 'widgets/pharmacy_nav_shell.dart';

class MedicalStoreShell extends StatefulWidget {
  const MedicalStoreShell({super.key});

  @override
  State<MedicalStoreShell> createState() => _MedicalStoreShellState();
}

class _MedicalStoreShellState extends State<MedicalStoreShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      RoleSessionGuard.verifyRole(context, UserType.medicalStore);
      _syncFirestoreForTab(_index);
    });
  }

  @override
  void dispose() {
    FirestoreScreenSync.detachPendingConnections();
    super.dispose();
  }

  void _onTabSelected(int index) {
    setState(() => _index = index);
    _syncFirestoreForTab(index);
  }

  void _syncFirestoreForTab(int index) {
    if (!ProfileCompletionService.instance.isComplete) return;
    if (index == 0 || index == 1 || index == 2) {
      final storeId = MedicalStoreSession.loggedInStoreId;
      FirestoreScreenSync.attachPendingConnections(
        role: UserType.medicalStore,
        profileId: storeId,
      );
      unawaited(
        PharmacyConnectionStore.instance.refreshActiveConnections(
          role: UserType.medicalStore,
          profileId: storeId,
          preferCache: true,
        ),
      );
    } else {
      FirestoreScreenSync.detachPendingConnections();
    }
  }

  List<int?> _navBadges(String storeId) {
    final newRx = PharmacyPrescriptionStore.instance
        .forStore(storeId)
        .where((d) => d.status == PharmacyDeliveryStatus.sent)
        .length;
    final connectPending = PharmacyConnectionStore.instance
            .pendingForStoreFromDoctor(storeId)
            .length +
        PharmacyConnectionStore.instance.pendingSentByStore(storeId).length;
    final unreadNotifications =
        PharmacyNotificationStore.instance.unreadCountForStore(storeId);

    return [newRx > 0 ? newRx : null, connectPending > 0 ? connectPending : null, unreadNotifications > 0 ? unreadNotifications : null, null];
  }

  @override
  Widget build(BuildContext context) {
    final storeId = MedicalStoreSession.loggedInStoreId;
    final store = MedicalStoreRegistry.findById(storeId);
    final storeName = store?.storeName ?? MedicalStoreSession.loggedInStoreName;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final storeTheme = isDark
        ? AppTheme.dark(AppColors.pharmacyGreen)
        : AppTheme.light(AppColors.pharmacyGreen);

    return Theme(
      data: storeTheme,
      child: ListenableBuilder(
        listenable: Listenable.merge([
          MedicalStoreRegistry.instance,
          PharmacyPrescriptionStore.instance,
          PharmacyConnectionStore.instance,
          PharmacyNotificationStore.instance,
        ]),
        builder: (context, _) {
          return PharmacyNavShell(
            selectedIndex: _index,
            onDestinationSelected: _onTabSelected,
            storeName: storeName,
            badges: _navBadges(storeId),
            child: IndexedStack(
              index: _index,
              children: [
                ProfileDataGate(
                  role: UserType.medicalStore,
                  child: const StoreDashboardScreen(),
                ),
                ProfileDataGate(
                  role: UserType.medicalStore,
                  child: const ConnectDoctorsScreen(),
                ),
                ProfileDataGate(
                  role: UserType.medicalStore,
                  child: const StoreNotificationsScreen(),
                ),
                const StoreProfileScreen(),
              ],
            ),
          );
        },
      ),
    );
  }
}
