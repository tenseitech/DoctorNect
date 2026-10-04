import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_colors.dart';

enum RoleCardVariant { mobile, web }

class RoleCard extends StatelessWidget {
  const RoleCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.onTap,
    this.variant = RoleCardVariant.web,
    this.isSelected = false,
  });

  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  final RoleCardVariant variant;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return _RoleCardSurface(
      title: title,
      subtitle: subtitle,
      color: color,
      icon: icon,
      onTap: onTap,
      variant: variant,
      isSelected: isSelected,
    );
  }
}

class _RoleCardSurface extends StatefulWidget {
  const _RoleCardSurface({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.onTap,
    required this.variant,
    required this.isSelected,
  });

  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  final RoleCardVariant variant;
  final bool isSelected;

  @override
  State<_RoleCardSurface> createState() => _RoleCardSurfaceState();
}

class _RoleCardSurfaceState extends State<_RoleCardSurface> {
  bool _hovered = false;
  bool _pressed = false;

  void _handleTap() {
    HapticFeedback.selectionClick();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final isWeb = widget.variant == RoleCardVariant.web;
    final color = widget.color;
    const radius = 16.0;

    final scale = _pressed ? 0.985 : (isWeb && _hovered ? 1.01 : 1.0);
    final lift = isWeb && _hovered && !_pressed ? -2.0 : 0.0;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        scale: scale,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          offset: Offset(0, lift / 100),
          child: Material(
            color: Colors.transparent,
            elevation: 0,
            borderRadius: BorderRadius.circular(radius),
            child: InkWell(
              onTap: _handleTap,
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) => setState(() => _pressed = false),
              onTapCancel: () => setState(() => _pressed = false),
              borderRadius: BorderRadius.circular(radius),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(
                    color: widget.isSelected
                        ? color
                        : (_hovered && isWeb
                            ? color.withValues(alpha: 0.45)
                            : (isDark
                                ? AppColors.borderOf(context)
                                : const Color(0xFFE2E8F0))),
                    width: widget.isSelected ? 2.0 : 1.0,
                  ),
                  boxShadow: widget.isSelected
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: isDark ? 0.25 : 0.14),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                          BoxShadow(
                            color: (isDark ? Colors.black : const Color(0xFF0F172A))
                                .withValues(alpha: isDark ? 0.20 : 0.03),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : _hovered && isWeb
                          ? [
                              BoxShadow(
                                color: color.withValues(alpha: isDark ? 0.16 : 0.08),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                              BoxShadow(
                                color: (isDark ? Colors.black : const Color(0xFF0F172A))
                                    .withValues(alpha: isDark ? 0.20 : 0.04),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : [
                              BoxShadow(
                                color: (isDark ? Colors.black : const Color(0xFF0F172A))
                                    .withValues(alpha: isDark ? 0.20 : 0.03),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                  color: widget.isSelected
                      ? color.withValues(alpha: isDark ? 0.16 : 0.07)
                      : (_hovered && isWeb
                          ? color.withValues(alpha: isDark ? 0.06 : 0.03)
                          : AppColors.surfaceOf(context)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Tinted rounded-square icon on the left (48px)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: widget.isSelected
                            ? color
                            : color.withValues(alpha: isDark ? 0.20 : 0.10),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: widget.isSelected
                              ? color
                              : color.withValues(alpha: isDark ? 0.32 : 0.18),
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          widget.icon,
                          color: widget.isSelected ? Colors.white : color,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Center: Bold title + full description (wraps up to 2 lines, NO ellipsis)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimaryOf(context),
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle,
                            maxLines: 2,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12.5,
                              fontWeight: FontWeight.w400,
                              height: 1.35,
                              color: AppColors.textSecondaryOf(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Right: Circular radio indicator (empty ring unselected, filled check selected)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      transitionBuilder: (child, anim) => ScaleTransition(
                        scale: anim,
                        child: FadeTransition(opacity: anim, child: child),
                      ),
                      child: widget.isSelected
                          ? Container(
                              key: const ValueKey('selected_check'),
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: color.withValues(alpha: 0.35),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.check_rounded,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : Container(
                              key: const ValueKey('unselected_radio'),
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isDark
                                      ? const Color(0xFF475569)
                                      : const Color(0xFFCBD5E1),
                                  width: 1.5,
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
