import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import '../../core/layout/responsive_layout.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../logout_button.dart';
import '../medibond_logo.dart';
import '../mobile_scaffold.dart';
import '../nav_request_dot.dart';
import '../overflow_safe_layout.dart';
import '../theme_toggle_button.dart';
import '../verified_badge_icon.dart';

const double roleMobileBottomNavBarHeight = 64.0;

class RoleNavItem {
  const RoleNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.mobileLabel,
    this.badgeCount,
    this.showDotBadge = false,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String? mobileLabel;
  final int? badgeCount;
  final bool showDotBadge;
}

class RoleShell extends StatelessWidget {
  const RoleShell({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.roleTitle,
    required this.entityName,
    this.entitySubtitle,
    required this.entityIcon,
    required this.accentColor,
    required this.accentGradientEnd,
    required this.navItems,
    required this.child,
    this.onLogout,
    this.headerTrailing,
    this.sidebarWidth = 268.0,
    this.contentMaxWidth,
    this.isVerified = false,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final String roleTitle;
  final String entityName;
  final String? entitySubtitle;
  final IconData entityIcon;
  final Color accentColor;
  final Color accentGradientEnd;
  final List<RoleNavItem> navItems;
  final Widget child;
  final VoidCallback? onLogout;
  final Widget? headerTrailing;
  final double sidebarWidth;
  final double? contentMaxWidth;
  final bool isVerified;

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
          bottomNavigationBar: _RoleBottomNav(
            selectedIndex: selectedIndex,
            onSelected: (index) => _handleDestinationSelected(context, index),
            navItems: navItems,
            accentColor: accentColor,
            accentGradientEnd: accentGradientEnd,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RoleMobileHeader(
                entityName: entityName,
                roleTitle: roleTitle,
                entitySubtitle: entitySubtitle,
                entityIcon: entityIcon,
                accentColor: accentColor,
                accentGradientEnd: accentGradientEnd,
                headerTrailing: headerTrailing,
                isVerified: isVerified,
              ),
              Expanded(child: child),
            ],
          ),
        ),
      );
    }

    final body = contentMaxWidth != null
        ? Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentMaxWidth!),
              child: child,
            ),
          )
        : child;

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
                width: sidebarWidth,
                child: _RoleSidebar(
                  entityName: entityName,
                  roleTitle: roleTitle,
                  entitySubtitle: entitySubtitle,
                  entityIcon: entityIcon,
                  accentColor: accentColor,
                  accentGradientEnd: accentGradientEnd,
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (index) =>
                      _handleDestinationSelected(context, index),
                  navItems: navItems,
                  onLogout: onLogout,
                  isVerified: isVerified,
                ),
              ),
              VerticalDivider(width: 1, color: AppColors.borderOf(context)),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleMobileHeader extends StatelessWidget {
  const _RoleMobileHeader({
    required this.entityName,
    required this.roleTitle,
    this.entitySubtitle,
    required this.entityIcon,
    required this.accentColor,
    required this.accentGradientEnd,
    this.headerTrailing,
    this.isVerified = false,
  });

  final String entityName;
  final String roleTitle;
  final String? entitySubtitle;
  final IconData entityIcon;
  final Color accentColor;
  final Color accentGradientEnd;
  final Widget? headerTrailing;
  final bool isVerified;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceOf(context),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: _RoleBrandBlock(
                  entityName: entityName,
                  roleTitle: roleTitle,
                  entitySubtitle: entitySubtitle,
                  entityIcon: entityIcon,
                  accentColor: accentColor,
                  accentGradientEnd: accentGradientEnd,
                  compact: true,
                  isVerified: isVerified,
                ),
              ),
              if (headerTrailing != null) ...[
                const SizedBox(width: 8),
                headerTrailing!,
              ],
              const SizedBox(width: 8),
              const ThemeToggleButton(highlighted: true),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleSidebar extends StatelessWidget {
  const _RoleSidebar({
    required this.entityName,
    required this.roleTitle,
    this.entitySubtitle,
    required this.entityIcon,
    required this.accentColor,
    required this.accentGradientEnd,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.navItems,
    this.onLogout,
    this.isVerified = false,
  });

  final String entityName;
  final String roleTitle;
  final String? entitySubtitle;
  final IconData entityIcon;
  final Color accentColor;
  final Color accentGradientEnd;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<RoleNavItem> navItems;
  final VoidCallback? onLogout;
  final bool isVerified;

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
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
            child: _RoleBrandBlock(
              entityName: entityName,
              roleTitle: roleTitle,
              entitySubtitle: entitySubtitle,
              entityIcon: entityIcon,
              accentColor: accentColor,
              accentGradientEnd: accentGradientEnd,
              compact: false,
              isVerified: isVerified,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Divider(
              height: 1,
              color: AppColors.borderOf(context).withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              itemCount: navItems.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final item = navItems[index];
                return _RoleNavTile(
                  icon: item.icon,
                  selectedIcon: item.selectedIcon,
                  label: item.label,
                  selected: index == selectedIndex,
                  badgeCount: item.badgeCount,
                  showDotBadge: item.showDotBadge,
                  accentColor: accentColor,
                  accentGradientEnd: accentGradientEnd,
                  onTap: () => onDestinationSelected(index),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Divider(
              height: 1,
              color: AppColors.borderOf(context).withValues(alpha: 0.9),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            child: onLogout != null
                ? OutlinedButton.icon(
                    onPressed: onLogout,
                    icon: const Icon(
                      Icons.logout,
                      size: 18,
                      color: AppColors.error,
                    ),
                    label: Text(
                      'Log out',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: AppTypography.bodySmall,
                        fontWeight: FontWeight.w600,
                        color: AppColors.error,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: AppColors.error.withValues(alpha: 0.35),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  )
                : const Center(child: LogoutTextButton()),
          ),
        ],
      ),
    );
  }
}

class _RoleBrandBlock extends StatelessWidget {
  const _RoleBrandBlock({
    required this.entityName,
    required this.roleTitle,
    this.entitySubtitle,
    required this.entityIcon,
    required this.accentColor,
    required this.accentGradientEnd,
    required this.compact,
    this.isVerified = false,
  });

  final String entityName;
  final String roleTitle;
  final String? entitySubtitle;
  final IconData entityIcon;
  final Color accentColor;
  final Color accentGradientEnd;
  final bool compact;
  final bool isVerified;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 40.0 : 44.0;
    final subtitle = entitySubtitle ?? roleTitle;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [accentColor, accentGradientEnd],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: 0.24),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(entityIcon, size: compact ? 22 : 24, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      entityName.isNotEmpty ? entityName : roleTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: compact ? 18 : 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: AppColors.textPrimaryOf(context),
                        height: 1.15,
                      ),
                    ),
                  ),
                  if (isVerified) ...[
                    const SizedBox(width: 6),
                    VerifiedBadgeIcon(size: compact ? 16 : 18),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 16,
                    height: 3,
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: compact ? 11 : 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondaryOf(context),
                      ),
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

class _RoleNavTile extends StatefulWidget {
  const _RoleNavTile({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.accentColor,
    required this.accentGradientEnd,
    this.badgeCount,
    this.showDotBadge = false,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accentColor;
  final Color accentGradientEnd;
  final int? badgeCount;
  final bool showDotBadge;

  @override
  State<_RoleNavTile> createState() => _RoleNavTileState();
}

class _RoleNavTileState extends State<_RoleNavTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final icon = widget.selected ? widget.selectedIcon : widget.icon;
    final iconColor =
        widget.selected ? Colors.white : AppColors.textPrimaryOf(context);
    final labelColor =
        widget.selected ? Colors.white : AppColors.textPrimaryOf(context);

    final decoration = widget.selected
        ? BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [widget.accentColor, widget.accentGradientEnd],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: widget.accentColor.withValues(alpha: 0.28),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          )
        : BoxDecoration(
            color: _hovered
                ? AppColors.textSecondaryOf(context).withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          );

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
            decoration: decoration,
            child: Row(
              children: [
                Icon(icon, size: 20, color: iconColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: AppTypography.bodySmall,
                      fontWeight:
                          widget.selected ? FontWeight.w700 : FontWeight.w500,
                      color: labelColor,
                    ),
                  ),
                ),
                if (widget.badgeCount != null && widget.badgeCount! > 0)
                  _BadgePill(
                    count: widget.badgeCount!,
                    accentColor: widget.accentColor,
                    selected: widget.selected,
                  )
                else if (widget.showDotBadge)
                  NavRequestDot(
                    color: widget.selected ? Colors.white : widget.accentColor,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BadgePill extends StatelessWidget {
  const _BadgePill({
    required this.count,
    required this.accentColor,
    required this.selected,
  });

  final int count;
  final Color accentColor;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: selected ? Colors.white : accentColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: AppTypography.labelSmall,
          fontWeight: FontWeight.w700,
          color: selected ? accentColor : Colors.white,
        ),
      ),
    );
  }
}

class _RoleBottomNav extends StatelessWidget {
  const _RoleBottomNav({
    required this.selectedIndex,
    required this.onSelected,
    required this.navItems,
    required this.accentColor,
    required this.accentGradientEnd,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<RoleNavItem> navItems;
  final Color accentColor;
  final Color accentGradientEnd;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context).withValues(alpha: 0.9),
            border: Border(top: BorderSide(color: AppColors.borderOf(context))),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: roleMobileBottomNavBarHeight,
              child: Row(
                children: List.generate(navItems.length, (index) {
                  final item = navItems[index];
                  final selected = index == selectedIndex;
                  final icon = selected ? item.selectedIcon : item.icon;
                  final iconColor = selected
                      ? Colors.white
                      : AppColors.textSecondaryOf(context);
                  final labelColor = selected
                      ? accentColor
                      : AppColors.textSecondaryOf(context);

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
                                    ? BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            accentColor,
                                            accentGradientEnd,
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        boxShadow: [
                                          BoxShadow(
                                            color: accentColor.withValues(
                                              alpha: 0.28,
                                            ),
                                            blurRadius: 8,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      )
                                    : const BoxDecoration(
                                        color: Colors.transparent,
                                      ),
                                child: Icon(icon, size: 22, color: iconColor),
                              ),
                              if (item.badgeCount != null &&
                                  item.badgeCount! > 0)
                                Positioned(
                                  right: 4,
                                  top: -2,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: accentColor,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      item.badgeCount! > 9
                                          ? '9+'
                                          : '${item.badgeCount}',
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                )
                              else if (item.showDotBadge)
                                Positioned(
                                  right: 4,
                                  top: -2,
                                  child: NavRequestDot(color: accentColor),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          SafeBottomNavLabel(
                            label: item.mobileLabel ??
                                compactBottomNavLabel(item.label),
                            style: TextStyle(
                              fontFamily: 'Inter',
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
