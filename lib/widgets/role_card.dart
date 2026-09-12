import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
  });

  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  final RoleCardVariant variant;

  @override
  Widget build(BuildContext context) {
    return _RoleCardSurface(
      title: title,
      subtitle: subtitle,
      color: color,
      icon: icon,
      onTap: onTap,
      variant: variant,
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
  });

  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  final RoleCardVariant variant;

  @override
  State<_RoleCardSurface> createState() => _RoleCardSurfaceState();
}

class _RoleCardSurfaceState extends State<_RoleCardSurface> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final isMobile = widget.variant == RoleCardVariant.mobile;
    final color = widget.color;
    final radius = isMobile ? 16.0 : 12.0;

    final scale = _pressed ? 0.97 : (_hovered && !isMobile ? 1.01 : 1.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        transform: Matrix4.diagonal3Values(scale, scale, 1.0),
        transformAlignment: Alignment.center,
        child: Material(
          color: AppColors.surfaceOf(context),
          elevation: 0,
          borderRadius: BorderRadius.circular(radius),
          child: InkWell(
            onTap: widget.onTap,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            borderRadius: BorderRadius.circular(radius),
            child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: _hovered && !isMobile
                    ? color.withValues(alpha: 0.4)
                    : AppColors.borderOf(context),
              ),
              boxShadow: isMobile
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.07),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : _hovered
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.1),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
              color: _hovered && !isMobile ? color.withValues(alpha: 0.03) : AppColors.surfaceOf(context),
            ),
            child: Row(
              children: [
                if (isMobile)
                  Container(
                    width: 4,
                    height: 72,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 14 : 16,
                      vertical: isMobile ? 14 : 14,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: isMobile ? 48 : 46,
                          height: isMobile ? 48 : 46,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                color,
                                Color.lerp(color, Colors.white, 0.22)!,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(isMobile ? 13 : 11),
                            boxShadow: [
                              BoxShadow(
                                color: color.withValues(alpha: 0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Icon(
                            widget.icon,
                            color: AppColors.surfaceOf(context),
                            size: isMobile ? 23 : 22,
                          ),
                        ),
                        SizedBox(width: isMobile ? 14 : 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: isMobile ? 16 : 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimaryOf(context),
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                widget.subtitle,
                                maxLines: isMobile ? 2 : 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: isMobile ? 12 : 12.5,
                                  height: 1.35,
                                  color: AppColors.textSecondaryOf(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 22,
                          color: _hovered || isMobile
                              ? color
                              : AppColors.textSecondaryOf(context).withValues(alpha: 0.55),
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
  );
}
}
