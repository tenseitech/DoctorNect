import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/layout/responsive_layout.dart';
import '../../../core/theme/app_colors.dart';
import '../../../widgets/logout_button.dart';
import '../../../widgets/medibond_logo.dart';
import '../../../widgets/mobile_scaffold.dart';
import '../../../widgets/nav_request_dot.dart';
import '../../../widgets/overflow_safe_layout.dart';
import '../../../widgets/theme_toggle_button.dart';
import '../../../core/theme/app_typography.dart';

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
const pharmacyMobileBottomNavBarHeight = 64.0;

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

abstract final class _PharmacyNavActiveStyle {
  static const _activeEnd = Color(0xFF047857);

  static BoxDecoration decoration({required bool selected}) {
    if (!selected) {
      return const BoxDecoration(color: Colors.transparent);
    }

    return BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.pharmacyGreen, _activeEnd],
      ),
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: AppColors.pharmacyGreen.withValues(alpha: 0.28),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  static Color iconColor(bool selected, BuildContext context) =>
      selected ? Colors.white : AppColors.textPrimaryOf(context);

  static Color labelColor(bool selected, BuildContext context) =>
      selected ? Colors.white : AppColors.textPrimaryOf(context);
}

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

  void _handleDestinationSelected(BuildContext context, int index) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
    }
    onDestinationSelected(index);
  }

  void _handleBackInvoked(BuildContext context, bool didPop) {
    if (didPop) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    if (selectedIndex != 0) {
      onDestinationSelected(0);
    }
  }

  int? _badgeFor(int index) => index < badges.length ? badges[index] : null;

  @override
  Widget build(BuildContext context) {
    final compact = ResponsiveLayout.isCompact(context);

    if (compact) {
      return PopScope(
        canPop: selectedIndex == 0 && !Navigator.of(context).canPop(),
        onPopInvokedWithResult: (didPop, _) =>
            _handleBackInvoked(context, didPop),
        child: MobileScaffold(
          padding: EdgeInsets.zero,
          extendBody: true,
          bottomNavigationBar: _PharmacyBottomNav(
            selectedIndex: selectedIndex,
            onSelected: (index) => _handleDestinationSelected(context, index),
            badges: badges,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PharmacyMobileHeader(storeName: storeName),
              Expanded(child: child),
            ],
          ),
        ),
      );
    }

    return PopScope(
      canPop: selectedIndex == 0 && !Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, _) =>
          _handleBackInvoked(context, didPop),
      child: Scaffold(
        backgroundColor: AppColors.cardBgOf(context),
        body: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 240,
                child: _PharmacySidebar(
                  storeName: storeName,
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (index) =>
                      _handleDestinationSelected(context, index),
                  badgeFor: _badgeFor,
                ),
              ),
              VerticalDivider(width: 1, color: AppColors.borderOf(context)),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _PharmacyMobileHeader extends StatelessWidget {
  const _PharmacyMobileHeader({required this.storeName});

  final String storeName;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceOf(context),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          child: Row(
            children: [
              Expanded(child: _BrandBlock(storeName: storeName, compact: true)),
              const SizedBox(width: 8),
              const ThemeToggleButton(highlighted: true),
            ],
          ),
        ),
      ),
    );
  }
}

class _PharmacySidebar extends StatelessWidget {
  const _PharmacySidebar({
    required this.storeName,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.badgeFor,
  });

  final String storeName;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final int? Function(int index) badgeFor;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surfaceOf(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                SidebarDoctorNectLogo(extended: true),
                ThemeToggleButton(highlighted: true),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: _BrandBlock(storeName: storeName, compact: false),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Divider(
                height: 1,
                color: AppColors.borderOf(context).withValues(alpha: 0.9)),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              itemCount: pharmacyNavTabs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final tab = pharmacyNavTabs[index];
                return _PharmacyNavTile(
                  icon: tab.icon,
                  selectedIcon: tab.selectedIcon,
                  label: tab.label,
                  selected: index == selectedIndex,
                  badge: badgeFor(index),
                  onTap: () => onDestinationSelected(index),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: Divider(
                height: 1,
                color: AppColors.borderOf(context).withValues(alpha: 0.9)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Center(child: LogoutTextButton()),
          ),
        ],
      ),
    );
  }
}

class _BrandBlock extends StatelessWidget {
  const _BrandBlock({required this.storeName, required this.compact});

  final String storeName;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PharmacyBrandLogo(compact: compact),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                storeName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: compact ? 20 : 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: AppColors.textPrimaryOf(context),
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 18,
                    height: 3,
                    decoration: BoxDecoration(
                      color: AppColors.pharmacyGreen,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Medical Store',
                    style: GoogleFonts.inter(
                      fontSize: compact ? 12 : 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PharmacyBrandLogo extends StatelessWidget {
  const _PharmacyBrandLogo({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 40.0 : 44.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.pharmacyGreen, Color(0xFF047857)],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.pharmacyGreen.withValues(alpha: 0.22),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(
        AppIcons.prescription,
        size: compact ? 22 : 24,
        color: AppColors.surfaceOf(context),
      ),
    );
  }
}

class _PharmacyNavTile extends StatefulWidget {
  const _PharmacyNavTile({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? badge;

  @override
  State<_PharmacyNavTile> createState() => _PharmacyNavTileState();
}

class _PharmacyNavTileState extends State<_PharmacyNavTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final icon = widget.selected ? widget.selectedIcon : widget.icon;
    final iconColor =
        _PharmacyNavActiveStyle.iconColor(widget.selected, context);
    final labelColor =
        _PharmacyNavActiveStyle.labelColor(widget.selected, context);
    final bg = widget.selected
        ? null
        : _hovered
            ? AppColors.textSecondaryOf(context).withValues(alpha: 0.06)
            : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: widget.selected
                ? _PharmacyNavActiveStyle.decoration(selected: true)
                : BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(12),
                  ),
            child: Row(
              children: [
                Icon(icon, size: 22, color: iconColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.label,
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.bodyLarge,
                      fontWeight:
                          widget.selected ? FontWeight.w700 : FontWeight.w500,
                      color: labelColor,
                    ),
                  ),
                ),
                if (widget.badge != null && widget.badge! > 0)
                  widget.label == 'Connect'
                      ? const NavRequestDot(color: AppColors.pharmacyGreen)
                      : _NavBadge(
                          count: widget.badge!, inverted: widget.selected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavBadge extends StatelessWidget {
  const _NavBadge({required this.count, this.inverted = false});

  final int count;
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color:
            inverted ? AppColors.surfaceOf(context) : AppColors.pharmacyGreen,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: AppTypography.labelSmall,
          fontWeight: FontWeight.w700,
          color:
              inverted ? AppColors.pharmacyGreen : AppColors.surfaceOf(context),
        ),
      ),
    );
  }
}

class _PharmacyBottomNav extends StatelessWidget {
  const _PharmacyBottomNav({
    required this.selectedIndex,
    required this.onSelected,
    required this.badges,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<int?> badges;

  int? _badgeFor(int index) => index < badges.length ? badges[index] : null;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context).withValues(alpha: 0.9),
            border: Border(
              top: BorderSide(color: AppColors.borderOf(context)),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: pharmacyMobileBottomNavBarHeight,
              child: Row(
                children: List.generate(pharmacyNavTabs.length, (index) {
                  final tab = pharmacyNavTabs[index];
                  final selected = index == selectedIndex;
                  final icon = selected ? tab.selectedIcon : tab.icon;
                  final iconColor =
                      _PharmacyNavActiveStyle.iconColor(selected, context);
                  final labelColor = selected
                      ? AppColors.pharmacyGreen
                      : AppColors.textSecondaryOf(context);
                  final badge = _badgeFor(index);

                  return Expanded(
                    child: InkWell(
                      onTap: () => onSelected(index),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOutCubic,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 5,
                                ),
                                decoration: selected
                                    ? _PharmacyNavActiveStyle.decoration(
                                        selected: true)
                                    : const BoxDecoration(
                                        color: Colors.transparent),
                                child: Icon(icon, size: 22, color: iconColor),
                              ),
                              if (badge != null && badge > 0)
                                Positioned(
                                  right: 4,
                                  top: -2,
                                  child: index == 1
                                      ? const NavRequestDot(
                                          color: AppColors.pharmacyGreen)
                                      : Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.pharmacyGreen,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            badge > 9 ? '9+' : '$badge',
                                            style: GoogleFonts.inter(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700,
                                              color:
                                                  AppColors.surfaceOf(context),
                                            ),
                                          ),
                                        ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          SafeBottomNavLabel(
                            label: compactBottomNavLabel(tab.label),
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                              color: labelColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
