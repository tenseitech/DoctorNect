import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/layout/responsive_layout.dart';
import '../../../core/theme/app_colors.dart';
import '../../../widgets/logout_button.dart';
import '../../../widgets/medibond_logo.dart';
import '../../../widgets/mobile_scaffold.dart';
import '../../../widgets/nav_request_dot.dart';
import '../../../widgets/overflow_safe_layout.dart';
import '../../../core/theme/app_typography.dart';

class PatientTabItem {
  const PatientTabItem({
    required this.outlinedIcon,
    required this.filledIcon,
    required this.label,
    this.shortLabel,
    this.customIconBuilder,
  });

  final IconData outlinedIcon;
  final IconData filledIcon;
  final String label;
  final String? shortLabel;
  final Widget Function(
          BuildContext context, bool selected, Color iconColor, double size)?
      customIconBuilder;

  String get mobileLabel => shortLabel ?? label;

  IconData icon({required bool selected}) =>
      selected ? filledIcon : outlinedIcon;

  Widget buildIcon(
    BuildContext context, {
    required bool selected,
    required Color iconColor,
    required double size,
  }) {
    if (customIconBuilder != null) {
      return customIconBuilder!(context, selected, iconColor, size);
    }
    return Icon(icon(selected: selected), size: size, color: iconColor);
  }
}

abstract final class _PatientNavActiveStyle {
  static const _activeEnd = Color(0xFF12836A);

  static BoxDecoration decoration({required bool selected}) {
    if (!selected) {
      return const BoxDecoration(color: Colors.transparent);
    }

    return BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.patientTeal, _activeEnd],
      ),
      borderRadius: BorderRadius.circular(12),
    );
  }

  static Color iconColor(BuildContext context, bool selected) {
    if (selected) return AppColors.white;
    return AppColors.isDark(context)
        ? const Color(0xFFCBD5E1)
        : const Color(0xFF64748B);
  }

  static Color labelColor(BuildContext context, bool selected) {
    if (selected) return AppColors.white;
    return AppColors.isDark(context)
        ? const Color(0xFFF1F5F9)
        : const Color(0xFF334155);
  }
}

class PatientAppShell extends StatelessWidget {
  const PatientAppShell({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.tabs,
    required this.child,
    this.requestDots = const [],
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<PatientTabItem> tabs;
  final Widget child;

  /// Per-tab request indicator dots (true = show dot).
  final List<bool> requestDots;

  bool _showDot(int index) => index < requestDots.length && requestDots[index];

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
          bottomNavigationBar: _PatientBottomTabBar(
            selectedIndex: selectedIndex,
            tabs: tabs,
            onSelected: (index) => _handleDestinationSelected(context, index),
            showDot: _showDot,
          ),
          child: child,
        ),
      );
    }

    final extended = ResponsiveLayout.isExpanded(context);

    return PopScope(
      canPop: selectedIndex == 0 && !Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, _) =>
          _handleBackInvoked(context, didPop),
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: extended ? 232 : 88,
                child: ColoredBox(
                  color: AppColors.surfaceOf(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                        child: SidebarDoctorNectLogo(extended: extended),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          itemCount: tabs.length,
                          itemBuilder: (context, index) {
                            return _PatientSideTabTile(
                              item: tabs[index],
                              selected: index == selectedIndex,
                              extended: extended,
                              showDot: _showDot(index),
                              onTap: () =>
                                  _handleDestinationSelected(context, index),
                            );
                          },
                        ),
                      ),
                      LogoutRailTile(extended: extended),
                      SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              VerticalDivider(
                  width: 1, thickness: 1, color: AppColors.borderOf(context)),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _PatientSideTabTile extends StatelessWidget {
  const _PatientSideTabTile({
    required this.item,
    required this.selected,
    required this.extended,
    required this.onTap,
    this.showDot = false,
  });

  final PatientTabItem item;
  final bool selected;
  final bool extended;
  final VoidCallback onTap;
  final bool showDot;

  Widget _iconWithDot(BuildContext context, Color iconColor, double size) {
    final icon = item.buildIcon(
      context,
      selected: selected,
      iconColor: iconColor,
      size: size,
    );
    if (!showDot) return icon;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -1,
          top: -1,
          child: NavRequestDot(
            color: AppColors.patientTeal,
            borderColor: selected ? AppColors.patientTeal : Colors.white,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isProfile = item.label == 'Profile';
    final iconColor = _PatientNavActiveStyle.iconColor(context, selected);
    final labelColor = (selected && isProfile)
        ? AppColors.patientTeal
        : _PatientNavActiveStyle.labelColor(context, selected);

    if (!extended) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Tooltip(
          message: item.label,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                height: 52,
                alignment: Alignment.center,
                decoration: (selected && isProfile)
                    ? BoxDecoration(
                        color: AppColors.patientTeal.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      )
                    : _PatientNavActiveStyle.decoration(selected: selected),
                child: _iconWithDot(context, iconColor, isProfile ? 32 : 24),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: (selected && isProfile)
                ? BoxDecoration(
                    color: AppColors.patientTeal.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  )
                : _PatientNavActiveStyle.decoration(selected: selected),
            child: Row(
              children: [
                _iconWithDot(context, iconColor, isProfile ? 32 : 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.bodyMedium,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: labelColor,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PatientBottomTabBar extends StatefulWidget {
  const _PatientBottomTabBar({
    required this.selectedIndex,
    required this.tabs,
    required this.onSelected,
    required this.showDot,
  });

  final int selectedIndex;
  final List<PatientTabItem> tabs;
  final ValueChanged<int> onSelected;
  final bool Function(int index) showDot;

  @override
  State<_PatientBottomTabBar> createState() => _PatientBottomTabBarState();
}

class _PatientBottomTabBarState extends State<_PatientBottomTabBar> {
  double? _startX;
  double? _startY;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Translucent frosted glass background matching WhatsApp pill (Image 2)
    final pillBg = isDark
        ? const Color(0x66111827) // ~40% opacity dark slate
        : const Color(0x99FFFFFF); // ~60% opacity crisp white
    final pillBorder = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.black.withValues(alpha: 0.08);

    return SafeArea(
      top: false,
      bottom: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(40),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(40),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                height: 64,
                decoration: BoxDecoration(
                  color: pillBg,
                  borderRadius: BorderRadius.circular(40),
                  border: Border.all(color: pillBorder, width: 1.0),
                ),
                child: Listener(
                  onPointerDown: (event) {
                    _startX = event.position.dx;
                    _startY = event.position.dy;
                  },
                  onPointerUp: (event) {
                    if (_startX == null || _startY == null) return;
                    final deltaX = event.position.dx - _startX!;
                    final deltaY = event.position.dy - _startY!;
                    _startX = null;
                    _startY = null;

                    if (deltaX.abs() > 40 && deltaY.abs() < 50) {
                      if (deltaX < 0 &&
                          widget.selectedIndex < widget.tabs.length - 1) {
                        widget.onSelected(widget.selectedIndex + 1);
                      } else if (deltaX > 0 && widget.selectedIndex > 0) {
                        widget.onSelected(widget.selectedIndex - 1);
                      }
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: List.generate(widget.tabs.length, (index) {
                        final selected = index == widget.selectedIndex;
                        final tab = widget.tabs[index];
                        final isProfile = tab.label == 'Profile';
                        final label = tab.mobileLabel;

                        // Active pill container matching Image 2 (WhatsApp style)
                        // Flat, no glow, no shadow
                        final activePillBg = isDark
                            ? const Color(0xFF1E2836)
                            : AppColors.patientTeal.withValues(alpha: 0.12);
                        final activePillBorder = isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : AppColors.patientTeal.withValues(alpha: 0.28);

                        final iconColor = selected
                            ? (isDark ? Colors.white : AppColors.patientTeal)
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.70)
                                : const Color(0xFF64748B));

                        final labelColor = selected
                            ? (isDark ? Colors.white : AppColors.patientTeal)
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.70)
                                : const Color(0xFF64748B));

                        return Expanded(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => widget.onSelected(index),
                              borderRadius: BorderRadius.circular(24),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOutCubic,
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 2, vertical: 5),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 2, vertical: 3),
                                decoration: selected
                                    ? BoxDecoration(
                                        color: activePillBg,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                            color: activePillBorder, width: 1),
                                      )
                                    : null,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      height: 28,
                                      child: Center(
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          alignment: Alignment.center,
                                          children: [
                                            tab.buildIcon(
                                              context,
                                              selected: selected,
                                              iconColor: iconColor,
                                              size: isProfile ? 28 : 22,
                                            ),
                                            if (widget.showDot(index))
                                              Positioned(
                                                right: isProfile ? -3 : -5,
                                                top: isProfile ? -1 : -2,
                                                child: NavRequestDot(
                                                  color: isDark
                                                      ? const Color(0xFF22C55E)
                                                      : AppColors.patientTeal,
                                                  borderColor: isDark
                                                      ? const Color(0xFF1E2836)
                                                      : Colors.white,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    SizedBox(
                                      height: 14,
                                      child: Center(
                                        child: SafeBottomNavLabel(
                                          label: compactBottomNavLabel(label),
                                          maxLines: 1,
                                          style: GoogleFonts.inter(
                                            fontSize: 10,
                                            height: 1.0,
                                            fontWeight: selected
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            color: labelColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
