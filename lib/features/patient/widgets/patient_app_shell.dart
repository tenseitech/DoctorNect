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
  });

  final IconData outlinedIcon;
  final IconData filledIcon;
  final String label;
  final String? shortLabel;

  String get mobileLabel => shortLabel ?? label;

  IconData icon({required bool selected}) => selected ? filledIcon : outlinedIcon;
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
      boxShadow: [
        BoxShadow(
          color: AppColors.patientTeal.withValues(alpha: 0.28),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
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

  bool _showDot(int index) =>
      index < requestDots.length && requestDots[index];

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
        onPopInvokedWithResult: (didPop, _) => _handleBackInvoked(context, didPop),
        child: MobileScaffold(
          padding: EdgeInsets.zero,
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
      onPopInvokedWithResult: (didPop, _) => _handleBackInvoked(context, didPop),
      child: Scaffold(
        backgroundColor: AppColors.cardBgOf(context),
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
                              onTap: () => _handleDestinationSelected(context, index),
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
              VerticalDivider(width: 1, thickness: 1, color: AppColors.borderOf(context)),
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

  Widget _iconWithDot(IconData iconData, Color iconColor, double size) {
    final icon = Icon(iconData, size: size, color: iconColor);
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
    final iconColor = _PatientNavActiveStyle.iconColor(context, selected);
    final labelColor = _PatientNavActiveStyle.labelColor(context, selected);

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
                decoration: _PatientNavActiveStyle.decoration(selected: selected),
                child: _iconWithDot(item.icon(selected: selected), iconColor, 24),
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
            decoration: _PatientNavActiveStyle.decoration(selected: selected),
            child: Row(
              children: [
                _iconWithDot(item.icon(selected: selected), iconColor, 22),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border(top: BorderSide(color: AppColors.borderOf(context).withValues(alpha: 0.9))),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimaryOf(context).withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
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
              if (deltaX < 0 && widget.selectedIndex < widget.tabs.length - 1) {
                widget.onSelected(widget.selectedIndex + 1);
              } else if (deltaX > 0 && widget.selectedIndex > 0) {
                widget.onSelected(widget.selectedIndex - 1);
              }
            }
          },
          child: SizedBox(
            height: widget.tabs.length >= 5 ? 66 : 60,
            child: Row(
              children: List.generate(widget.tabs.length, (index) {
                final selected = index == widget.selectedIndex;
                final tab = widget.tabs[index];
                final iconColor = _PatientNavActiveStyle.iconColor(context, selected);
                final label = tab.mobileLabel;

                return Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => widget.onSelected(index),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOutCubic,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                                decoration: BoxDecoration(
                                  gradient: selected
                                      ? const LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [AppColors.patientTeal, Color(0xFF12836A)],
                                        )
                                      : null,
                                  color: selected ? null : Colors.transparent,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: selected
                                      ? [
                                          BoxShadow(
                                            color: AppColors.patientTeal.withValues(alpha: 0.22),
                                            blurRadius: 8,
                                            offset: const Offset(0, 3),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Icon(
                                  tab.icon(selected: selected),
                                  size: 24,
                                  color: iconColor,
                                ),
                              ),
                              if (widget.showDot(index))
                                Positioned(
                                  right: 6,
                                  top: -2,
                                  child: NavRequestDot(
                                    color: AppColors.patientTeal,
                                    borderColor: selected ? AppColors.patientTeal : Colors.white,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          SafeBottomNavLabel(
                            label: compactBottomNavLabel(label),
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              height: 1.1,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                              color: selected ? AppColors.patientTeal : AppColors.textSecondaryOf(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
