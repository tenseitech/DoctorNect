import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';

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
  State<_RoleCardSurface> createState() => _RoleCardSurfaceState();
}

class _RoleCardSurfaceState extends State<_RoleCardSurface> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final isMobile = widget.variant == RoleCardVariant.mobile;
    final isWeb = !isMobile;
    final color = widget.color;
    const radius = 14.0;

    final scale = _pressed ? 0.985 : (isWeb && _hovered ? 1.010 : 1.0);
    final lift = isWeb && _hovered && !_pressed ? -2.5 : 0.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        scale: scale,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          offset: Offset(0, lift / 100),
          child: Material(
            color: Colors.transparent,
            elevation: 0,
            borderRadius: BorderRadius.circular(radius),
            child: InkWell(
              onTap: widget.onTap,
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) => setState(() => _pressed = false),
              onTapCancel: () => setState(() => _pressed = false),
              borderRadius: BorderRadius.circular(radius),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(
                    color: widget.isSelected
                        ? color
                        : (_hovered && isWeb
                            ? color.withValues(alpha: 0.50)
                            : (isDark
                                ? AppColors.borderOf(context)
                                : const Color(0xFFE2E8F0))),
                    width: widget.isSelected
                        ? 2.0
                        : (_hovered && isWeb ? 1.5 : 1.0),
                  ),
                  boxShadow: isMobile
                      ? [
                          BoxShadow(
                            color: (isDark
                                    ? Colors.black
                                    : const Color(0xFF0F172A))
                                .withValues(alpha: isDark ? 0.28 : 0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                          BoxShadow(
                            color: color.withValues(alpha: isDark ? 0.08 : 0.03),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : _hovered || widget.isSelected
                          ? [
                              BoxShadow(
                                color: color.withValues(alpha: isDark ? 0.22 : 0.14),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                              BoxShadow(
                                color: (isDark
                                        ? Colors.black
                                        : const Color(0xFF0F172A))
                                    .withValues(alpha: isDark ? 0.28 : 0.04),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : [
                              BoxShadow(
                                color: (isDark
                                        ? Colors.black
                                        : const Color(0xFF0F172A))
                                    .withValues(alpha: isDark ? 0.24 : 0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                              BoxShadow(
                                color: color.withValues(alpha: isDark ? 0.05 : 0.02),
                                blurRadius: 6,
                                offset: const Offset(0, 1),
                              ),
                            ],
                  color: widget.isSelected
                      ? color.withValues(alpha: isDark ? 0.16 : 0.08)
                      : (_hovered && isWeb
                          ? color.withValues(alpha: isDark ? 0.09 : 0.038)
                          : AppColors.surfaceOf(context)),
                ),
                child: Row(
                  children: [
                    if (isMobile)
                      Container(
                        width: 4,
                        height: 72,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(radius),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 14 : 16,
                          vertical: isMobile ? 13 : 13,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: isMobile ? 46 : 44,
                              height: isMobile ? 46 : 44,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    color,
                                    Color.lerp(color, Colors.white, 0.20)!,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: color.withValues(alpha: 0.26),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Icon(
                                widget.icon,
                                color: Colors.white,
                                size: isMobile ? 22 : 21,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: isMobile
                                          ? AppTypography.titleMedium
                                          : AppTypography.bodyLarge,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimaryOf(context),
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    widget.subtitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: AppTypography.labelMedium,
                                      height: 1.35,
                                      color: AppColors.textSecondaryOf(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (widget.isSelected)
                              Icon(
                                Icons.check_circle_rounded,
                                size: 22,
                                color: color,
                              )
                            else
                              AnimatedSlide(
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOutCubic,
                                offset: Offset(_hovered && isWeb ? 0.15 : 0, 0),
                                child: Icon(
                                  Icons.chevron_right_rounded,
                                  size: 22,
                                  color: _hovered || isMobile
                                      ? color
                                      : AppColors.textSecondaryOf(context)
                                          .withValues(alpha: 0.45),
                                ),
                              ),
                          ],
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
