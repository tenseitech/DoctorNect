import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/layout/responsive_layout.dart';
import '../../../core/theme/app_colors.dart';
import '../../../widgets/shell/role_shell.dart';

class PharmacyNavTab {
  const PharmacyNavTab({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Fixed bar height inside [SafeArea] on compact (mobile) layout.
const pharmacyMobileBottomNavBarHeight = roleMobileBottomNavBarHeight;

/// Bottom [ListView] padding for compact tabs under [PharmacyNavShell] (`extendBody: true`).
double pharmacyMobileScrollBottomPadding(BuildContext context) {
  if (!ResponsiveLayout.isCompact(context)) return 32.0;

  final mq = MediaQuery.of(context);
  var bottomInset = math.max(mq.viewPadding.bottom, mq.padding.bottom);

  // iPhone Safari web often reports 0 safe-area; home-indicator devices need ~34px.
  if (bottomInset == 0 && kIsWeb) {
    bottomInset = 34.0;
  }

  return pharmacyMobileBottomNavBarHeight + bottomInset + 32.0;
}

const pharmacyNavTabs = [
  PharmacyNavTab(
    icon: AppIcons.prescription,
    selectedIcon: AppIcons.prescription,
    label: 'Prescriptions',
  ),
  PharmacyNavTab(
    icon: TablerIcons.link,
    selectedIcon: TablerIcons.link,
    label: 'Connect',
  ),
  PharmacyNavTab(
    icon: TablerIcons.bell,
    selectedIcon: TablerIcons.bell_filled,
    label: 'Notifications',
  ),
  PharmacyNavTab(
    icon: TablerIcons.user,
    selectedIcon: TablerIcons.user_filled,
    label: 'Profile',
  ),
];

class PharmacyNavShell extends StatelessWidget {
  const PharmacyNavShell({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.child,
    required this.storeName,
    this.badges = const [],
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget child;
  final String storeName;
  final List<int?> badges;

  int? _badgeFor(int index) => index < badges.length ? badges[index] : null;

  @override
  Widget build(BuildContext context) {
    return RoleShell(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      roleTitle: 'Medical Store',
      entityName: storeName,
      entityIcon: AppIcons.prescription,
      accentColor: AppColors.pharmacyGreen,
      accentGradientEnd: const Color(0xFF047857),
      sidebarWidth: 268.0,
      navItems: List.generate(pharmacyNavTabs.length, (index) {
        final tab = pharmacyNavTabs[index];
        final badge = _badgeFor(index);
        return RoleNavItem(
          icon: tab.icon,
          selectedIcon: tab.selectedIcon,
          label: tab.label,
          badgeCount: index == 1 ? null : badge,
          showDotBadge: index == 1 && (badge != null && badge > 0),
        );
      }),
      child: child,
    );
  }
}
