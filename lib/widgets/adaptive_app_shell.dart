import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/layout/responsive_layout.dart';
import '../core/theme/app_colors.dart';
import 'logout_button.dart';
import 'medibond_logo.dart';
import 'mobile_scaffold.dart';
import 'nav_request_dot.dart';
import 'overflow_safe_layout.dart';
import '../core/theme/app_typography.dart';

/// Bottom nav on phone; side rail on tablet/desktop web — same tabs, no missing features.
class AdaptiveAppShell extends StatelessWidget {
  const AdaptiveAppShell({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    required this.child,
    this.accentColor,
    this.glassmorphic = false,
    this.filledActiveTabs = false,
    this.leadingHeader,
    this.trailingFooter,
    this.showMobileLogout = true,
    this.showMobileTopBar = true,
    this.requestDots = const [],
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;
  final Widget child;
  final Color? accentColor;
  final bool glassmorphic;
  final bool filledActiveTabs;
  final Widget? leadingHeader;
  final Widget? trailingFooter;
  final bool showMobileLogout;
  final bool showMobileTopBar;
  /// Per-tab request indicator dots (true = show dot).
  final List<bool> requestDots;

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
        canPop: Navigator.of(context).canPop() || selectedIndex == 0,
        onPopInvokedWithResult: (didPop, _) => _handleBackInvoked(context, didPop),
        child: MobileScaffold(
          padding: EdgeInsets.zero,
          extendBody: glassmorphic,
          bottomNavigationBar: _CompactBottomNavBar(
            selectedIndex: selectedIndex,
            accentColor: accentColor ?? Theme.of(context).colorScheme.primary,
            destinations: destinations,
            onSelected: (index) => _handleDestinationSelected(context, index),
            glassmorphic: glassmorphic,
            filledActiveTabs: filledActiveTabs,
            requestDots: requestDots,
          ),
          child: showMobileTopBar
              ? Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(child: leadingHeader ?? const SizedBox.shrink()),
                          if (showMobileLogout) LogoutIconButton(color: accentColor),
                        ],
                      ),
                    ),
                    Expanded(child: child),
                  ],
                )
              : child,
        ),
      );
    }

    final primary = accentColor ?? Theme.of(context).colorScheme.primary;
    final railWidth = ResponsiveLayout.isExpanded(context) ? 240.0 : 80.0;

    final extended = ResponsiveLayout.isExpanded(context);

    return PopScope(
      canPop: selectedIndex == 0 && !Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, _) => _handleBackInvoked(context, didPop),
      child: Scaffold(
        body: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: railWidth,
                child: _CustomSidebar(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (index) => _handleDestinationSelected(context, index),
                  destinations: destinations,
                  extended: extended,
                  accentColor: primary,
                  filledActiveTabs: filledActiveTabs,
                  leadingHeader: leadingHeader ?? SidebarDoctorNectLogo(extended: extended),
                  trailingFooter: trailingFooter,
                  requestDots: requestDots,
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

abstract final class _FilledNavActiveStyle {
  static Color _activeEnd(Color accent) => Color.lerp(accent, const Color(0xFF0B1F33), 0.35)!;

  static BoxDecoration decoration({required bool selected, required Color accent}) {
    if (!selected) {
      return const BoxDecoration(color: Colors.transparent);
    }

    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [accent, _activeEnd(accent)],
      ),
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: accent.withValues(alpha: 0.22),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }

  static Color iconColor({
    required bool selected,
    required bool filled,
    required Color accent,
    bool isDark = false,
  }) {
    if (selected && filled) return Colors.white;
    if (selected) return accent;
    return isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
  }

  static Color labelColor({
    required bool selected,
    required bool filled,
    required Color accent,
    bool isDark = false,
  }) {
    if (selected && filled) return Colors.white;
    if (selected) return accent;
    return isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
  }
}

class _CustomSidebar extends StatefulWidget {
  const _CustomSidebar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    required this.extended,
    required this.accentColor,
    this.filledActiveTabs = false,
    this.leadingHeader,
    this.trailingFooter,
    this.requestDots = const [],
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;
  final bool extended;
  final Color accentColor;
  final bool filledActiveTabs;
  final Widget? leadingHeader;
  final Widget? trailingFooter;
  final List<bool> requestDots;

  bool _showDot(int index) =>
      index < requestDots.length && requestDots[index];

  @override
  State<_CustomSidebar> createState() => _CustomSidebarState();
}

class _CustomSidebarState extends State<_CustomSidebar> {
  int? _hoverIndex;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.leadingHeader != null) ...[
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              child: widget.leadingHeader!,
            ),
          ),
        ] else
          const SafeArea(bottom: false, child: SizedBox(height: 20)),
        Expanded(
          child: ListView.separated(
            padding: EdgeInsets.symmetric(horizontal: widget.extended ? 16 : 8),
            itemCount: widget.destinations.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (context, index) {
              final d = widget.destinations[index];
              final selected = index == widget.selectedIndex;
              final icon = selected ? (d.selectedIcon ?? d.icon) : d.icon;
              final isHovered = _hoverIndex == index;
              final isDark = Theme.of(context).brightness == Brightness.dark;
              final iconColor = _FilledNavActiveStyle.iconColor(
                selected: selected,
                filled: widget.filledActiveTabs,
                accent: widget.accentColor,
                isDark: isDark,
              );
              final labelColor = _FilledNavActiveStyle.labelColor(
                selected: selected,
                filled: widget.filledActiveTabs,
                accent: widget.accentColor,
                isDark: isDark,
              );

              return MouseRegion(
                onEnter: (_) => setState(() => _hoverIndex = index),
                onExit: (_) => setState(() => _hoverIndex = null),
                child: InkWell(
                  onTap: () => widget.onDestinationSelected(index),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.symmetric(
                      horizontal: widget.extended ? 16 : 0, 
                      vertical: widget.extended ? 12 : 12
                    ),
                    decoration: widget.filledActiveTabs
                        ? (selected
                            ? _FilledNavActiveStyle.decoration(
                                selected: true,
                                accent: widget.accentColor,
                              )
                            : BoxDecoration(
                                color: isHovered
                                    ? AppColors.textSecondaryOf(context).withValues(alpha: 0.06)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ))
                        : BoxDecoration(
                            color: selected 
                                ? widget.accentColor.withValues(alpha: 0.12) 
                                : isHovered 
                                    ? AppColors.textSecondaryOf(context).withValues(alpha: 0.05)
                                    : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                    child: Row(
                      mainAxisAlignment: widget.extended ? MainAxisAlignment.start : MainAxisAlignment.center,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            IconTheme(
                              data: IconThemeData(
                                color: iconColor,
                                size: 24,
                              ),
                              child: icon,
                            ),
                            if (widget._showDot(index))
                              Positioned(
                                right: -1,
                                top: -1,
                                child: NavRequestDot(
                                  color: widget.accentColor,
                                  borderColor: selected && widget.filledActiveTabs
                                      ? widget.accentColor
                                      : Colors.white,
                                ),
                              ),
                          ],
                        ),
                        if (widget.extended) ...[
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              d.label,
                              style: GoogleFonts.inter(
                                fontSize: AppTypography.bodyLarge,
                                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                                color: labelColor,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (widget.trailingFooter != null) ...[
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: widget.trailingFooter!,
            ),
          ),
        ] else ...[
          LogoutRailTile(extended: widget.extended),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _CompactBottomNavBar extends StatefulWidget {
  const _CompactBottomNavBar({
    required this.selectedIndex,
    required this.accentColor,
    required this.destinations,
    required this.onSelected,
    this.glassmorphic = false,
    this.filledActiveTabs = false,
    this.requestDots = const [],
  });

  final int selectedIndex;
  final Color accentColor;
  final List<NavigationDestination> destinations;
  final ValueChanged<int> onSelected;
  final bool glassmorphic;
  final bool filledActiveTabs;
  final List<bool> requestDots;

  bool _showDot(int index) =>
      index < requestDots.length && requestDots[index];

  @override
  State<_CompactBottomNavBar> createState() => _CompactBottomNavBarState();
}

class _CompactBottomNavBarState extends State<_CompactBottomNavBar> {
  double? _startX;
  double? _startY;

  static String _navLabel(String label) => compactBottomNavLabel(label);

  IconData? _iconData(Widget? widget) {
    if (widget is Icon) return widget.icon;
    return null;
  }

  double _iconSize(Widget? widget, {required bool selected}) {
    if (widget is Icon && widget.size != null) return widget.size!;
    return selected ? 24 : 22;
  }

  @override
  Widget build(BuildContext context) {
    final tabCount = widget.destinations.length;
    final barHeight = tabCount >= 5
        ? (widget.filledActiveTabs ? 72.0 : 70.0)
        : (widget.filledActiveTabs ? 64.0 : 62.0);

    final navBarContent = SafeArea(
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

          // Reset start coordinates
          _startX = null;
          _startY = null;

          // Define swipe detection criteria:
          // 1. Horizontal movement is significant (e.g. > 40 pixels)
          // 2. Vertical movement is small to prevent diagonal scrolling/swipes from triggering it
          if (deltaX.abs() > 40 && deltaY.abs() < 50) {
            if (deltaX < 0) {
              // Swiped left -> Next tab
              if (widget.selectedIndex < widget.destinations.length - 1) {
                widget.onSelected(widget.selectedIndex + 1);
              }
            } else {
              // Swiped right -> Previous tab
              if (widget.selectedIndex > 0) {
                widget.onSelected(widget.selectedIndex - 1);
              }
            }
          }
        },
        child: SizedBox(
          height: barHeight,
          child: Row(
            children: List.generate(widget.destinations.length, (i) {
              final selected = i == widget.selectedIndex;
              final dest = widget.destinations[i];
              final iconWidget = selected ? (dest.selectedIcon ?? dest.icon) : dest.icon;
              final iconData = _iconData(iconWidget);
              final iconColor = _FilledNavActiveStyle.iconColor(
                selected: selected,
                filled: widget.filledActiveTabs,
                accent: widget.accentColor,
              );
              final labelColor = widget.filledActiveTabs && selected
                  ? widget.accentColor
                  : selected
                      ? widget.accentColor
                      : Theme.of(context).brightness == Brightness.dark
                          ? AppColors.darkTextSecondary
                          : AppColors.textSecondaryOf(context);

              return Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => widget.onSelected(i),
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOutCubic,
                                width: widget.filledActiveTabs && selected ? 40 : null,
                                height: widget.filledActiveTabs && selected ? 40 : null,
                                alignment: Alignment.center,
                                padding: widget.filledActiveTabs && selected
                                    ? EdgeInsets.zero
                                    : EdgeInsets.symmetric(
                                        horizontal: widget.filledActiveTabs ? 14 : 12,
                                        vertical: widget.filledActiveTabs ? 5 : 4,
                                      ),
                                decoration: widget.filledActiveTabs
                                    ? _FilledNavActiveStyle.decoration(
                                        selected: selected,
                                        accent: widget.accentColor,
                                      )
                                    : BoxDecoration(
                                        color: selected
                                            ? widget.accentColor.withValues(alpha: 0.12)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                child: iconData != null
                                    ? Icon(
                                        iconData,
                                        size: widget.filledActiveTabs && selected
                                            ? 22
                                            : _iconSize(iconWidget, selected: selected),
                                        color: iconColor,
                                      )
                                    : IconTheme(
                                        data: IconThemeData(
                                          color: iconColor,
                                          size: widget.filledActiveTabs && selected
                                              ? 22
                                              : _iconSize(iconWidget, selected: selected),
                                        ),
                                        child: iconWidget,
                                      ),
                              ),
                              if (widget._showDot(i))
                                Positioned(
                                  right: widget.filledActiveTabs && selected ? 2 : 6,
                                  top: widget.filledActiveTabs && selected ? 2 : 0,
                                  child: NavRequestDot(
                                    color: widget.accentColor,
                                    borderColor: selected && widget.filledActiveTabs
                                        ? widget.accentColor
                                        : Colors.white,
                                  ),
                                ),
                            ],
                          ),
                        const SizedBox(height: 2),
                        SafeBottomNavLabel(
                          label: _navLabel(dest.label),
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            height: 1.1,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            color: labelColor,
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
    );

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final navBg = isDark
        ? AppColors.darkSurface.withValues(alpha: 0.92)
        : Colors.white.withValues(alpha: 0.76);
    final borderClr = isDark
        ? AppColors.darkBorder
        : Colors.black.withValues(alpha: 0.08);

    if (widget.glassmorphic) {
      return ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18.0, sigmaY: 18.0),
          child: Container(
            decoration: BoxDecoration(
              color: navBg,
              border: Border(
                top: BorderSide(
                  color: borderClr,
                  width: 0.5,
                ),
              ),
            ),
            child: navBarContent,
          ),
        ),
      );
    }

    return Material(
      elevation: 8,
      shadowColor: Colors.black12,
      color: Theme.of(context).colorScheme.surface,
      child: navBarContent,
    );
  }
}
