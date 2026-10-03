import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_controller.dart';
import '../../../core/theme/app_typography.dart';

/// Design tokens matching the main login screen (source of truth).
abstract final class AuthBrandTheme {
  static const double sheetRadius = 28.0;
  static const double desktopCardRadius = 22.0;
  static const double inputRadius = 12.0;
  static const double desktopInputRadius = 14.0;
  static const double mobileHorizontalPadding = 22.0;

  static const Color desktopRightBg = Color(0xFFF7F9FC);
  static const Color desktopRightBgTint = Color(0xFFEEF3FB);
  static const Color meshSky = Color(0xFF38BDF8);

  /// Signature DoctorNect Navy-Blue brand gradient for desktop left panel.
  static const List<Color> desktopBrandGradient = [
    Color(0xFF082555),
    Color(0xFF0A2F6B),
    Color(0xFF123E8A),
    AppColors.doctorBlue,
  ];

  /// Signature DoctorNect Navy-Blue hero gradient for mobile headers.
  static const List<Color> mobileHeroGradient = [
    Color(0xFF061D42),
    Color(0xFF0A2F6B),
    Color(0xFF123E8A),
    AppColors.doctorBlue,
    Color(0xFF2E6FF2),
  ];

  /// 3-tier deep soft elevation matching the main login card.
  static List<BoxShadow> desktopCardShadows(
    BuildContext context, {
    Color accent = AppColors.doctorBlue,
  }) {
    final isDark = AppColors.isDark(context);
    return [
      BoxShadow(
        color: isDark
            ? Colors.black.withValues(alpha: 0.42)
            : const Color(0xFF0B1841).withValues(alpha: 0.10),
        blurRadius: 48,
        offset: const Offset(0, 24),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.06),
        blurRadius: 24,
      ),
      BoxShadow(
        color: accent.withValues(alpha: isDark ? 0.10 : 0.06),
        blurRadius: 60,
        spreadRadius: -12,
        offset: const Offset(0, 12),
      ),
    ];
  }

  /// Dual-tier elevation matching the mobile auth bottom sheet.
  static List<BoxShadow> mobileSheetShadows(BuildContext context) {
    final isDark = AppColors.isDark(context);
    return [
      BoxShadow(
        color: isDark
            ? Colors.black.withValues(alpha: 0.42)
            : const Color(0xFF0B1841).withValues(alpha: 0.20),
        blurRadius: 36,
        offset: const Offset(0, -14),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.06),
        blurRadius: 10,
        offset: const Offset(0, -2),
      ),
    ];
  }
}

/// Blurred circular glow used for background depth.
class AuthSoftGlow extends StatelessWidget {
  const AuthSoftGlow({super.key, required this.diameter, required this.color});

  final double diameter;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

/// Subtle dot lattice overlay.
class AuthDotLatticePainter extends CustomPainter {
  const AuthDotLatticePainter();

  static const _spacing = 26.0;
  static const _radius = 1.1;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.07);

    for (var y = _spacing; y < size.height; y += _spacing) {
      for (var x = _spacing; x < size.width; x += _spacing) {
        canvas.drawCircle(Offset(x, y), _radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(AuthDotLatticePainter oldDelegate) => false;
}

/// Concentric line-art rings with cardiac monitor pulse icon.
class AuthBrandGraphic extends StatelessWidget {
  const AuthBrandGraphic({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AuthSoftGlow(
              diameter: size * 0.95,
              color: AuthBrandTheme.meshSky.withValues(alpha: 0.20),
            ),
            CustomPaint(
              size: Size.square(size),
              painter: const _AuthBrandGraphicPainter(),
            ),
            Icon(
              Icons.monitor_heart_outlined,
              size: size * 0.30,
              color: Colors.white.withValues(alpha: 0.20),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthBrandGraphicPainter extends CustomPainter {
  const _AuthBrandGraphicPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withValues(alpha: 0.14)
      ..strokeWidth = 1.2;

    for (final factor in const [0.30, 0.40, 0.50]) {
      canvas.drawCircle(center, size.width * factor, ring);
    }

    final dashRing = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 1.0;

    canvas.drawCircle(center, size.width * 0.60, dashRing);
  }

  @override
  bool shouldRepaint(_AuthBrandGraphicPainter oldDelegate) => false;
}

/// Layered glow blobs and dot lattice for desktop left brand panel.
class AuthDesktopBrandBackdrop extends StatelessWidget {
  const AuthDesktopBrandBackdrop({
    super.key,
    this.accent = AppColors.doctorBlue,
  });

  final Color accent;

  @override
  Widget build(BuildContext context) {
    final highlight = Color.lerp(accent, Colors.white, 0.35) ?? accent;
    final lift = Color.lerp(accent, Colors.white, 0.18) ?? accent;

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -220,
            left: -180,
            child: AuthSoftGlow(
              diameter: 620,
              color: accent.withValues(alpha: 0.55),
            ),
          ),
          Positioned(
            top: -140,
            right: -190,
            child: AuthSoftGlow(
              diameter: 520,
              color: highlight.withValues(alpha: 0.28),
            ),
          ),
          Positioned(
            bottom: -260,
            left: -140,
            child: AuthSoftGlow(
              diameter: 600,
              color: lift.withValues(alpha: 0.30),
            ),
          ),
          Positioned(
            bottom: -200,
            right: -120,
            child: AuthSoftGlow(
              diameter: 460,
              color: accent.withValues(alpha: 0.34),
            ),
          ),
          const Opacity(
            opacity: 0.55,
            child: CustomPaint(painter: AuthDotLatticePainter()),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  const Color(0xFF0B1841).withValues(alpha: 0.34),
                ],
                stops: const [0.55, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Subtle glow backdrop for the desktop right content panel.
class AuthDesktopAuthBackdrop extends StatelessWidget {
  const AuthDesktopAuthBackdrop({
    super.key,
    this.accent = AppColors.doctorBlue,
  });

  final Color accent;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;

          return Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: -w * 0.22,
                top: -h * 0.12,
                child: AuthSoftGlow(
                  diameter: w * 0.72,
                  color: accent.withValues(alpha: isDark ? 0.14 : 0.10),
                ),
              ),
              Positioned(
                right: -w * 0.18,
                top: h * 0.08,
                child: AuthSoftGlow(
                  diameter: w * 0.55,
                  color: accent.withValues(alpha: isDark ? 0.12 : 0.08),
                ),
              ),
              Positioned(
                left: w * 0.08,
                bottom: -h * 0.14,
                child: AuthSoftGlow(
                  diameter: w * 0.62,
                  color: accent.withValues(alpha: isDark ? 0.10 : 0.07),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Mobile hero background layer.
class AuthMobileBrandBackdrop extends StatelessWidget {
  const AuthMobileBrandBackdrop({
    super.key,
    required this.width,
    this.accent = AppColors.doctorBlue,
  });

  final double width;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final highlight = Color.lerp(accent, Colors.white, 0.35) ?? accent;

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -width * 0.40,
            left: -width * 0.35,
            child: AuthSoftGlow(
              diameter: width * 1.05,
              color: accent.withValues(alpha: 0.50),
            ),
          ),
          Positioned(
            top: -width * 0.20,
            right: -width * 0.40,
            child: AuthSoftGlow(
              diameter: width * 0.95,
              color: highlight.withValues(alpha: 0.25),
            ),
          ),
          const Opacity(
            opacity: 0.45,
            child: CustomPaint(painter: AuthDotLatticePainter()),
          ),
        ],
      ),
    );
  }
}

/// Brand mark: 34x34 white square container with icon + DoctorNect text.
class AuthDesktopBrandMark extends StatelessWidget {
  const AuthDesktopBrandMark({
    super.key,
    this.accent = AppColors.doctorBlue,
    this.icon = Icons.local_hospital_rounded,
  });

  final Color accent;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 19, color: accent),
        ),
        const SizedBox(width: 12),
        Text(
          'DoctorNect',
          style: TextStyle(fontFamily: 'Inter', 
            fontSize: 21,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: -0.4,
            height: 1,
          ),
        ),
      ],
    );
  }
}

/// Wordmark for the narrow/mobile header.
class AuthMobileBrandWordmark extends StatelessWidget {
  const AuthMobileBrandWordmark({super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      'DoctorNect',
      style: TextStyle(fontFamily: 'Inter', 
        fontSize: AppTypography.displayMedium,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        height: 1.1,
        color: Colors.white,
      ),
    );
  }
}

/// Circular theme toggle for the desktop auth panel (matches main login screen).
class AuthDesktopThemeToggle extends StatelessWidget {
  const AuthDesktopThemeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppThemeController.instance,
      builder: (context, _) {
        final isDark = AppThemeController.instance.isDarkMode;
        final tooltip = isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode';
        final iconColor = isDark
            ? const Color(0xFFFDE047)
            : AppColors.textSecondaryOf(context);

        return Tooltip(
          message: tooltip,
          child: Material(
            color: AppColors.surfaceOf(context),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: AppThemeController.instance.toggleTheme,
              customBorder: const CircleBorder(),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.borderOf(context)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, anim) =>
                      ScaleTransition(scale: anim, child: child),
                  child: Icon(
                    isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                    key: ValueKey(isDark),
                    color: iconColor,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Circular theme toggle for mobile hero bar (matches main login screen).
class AuthMobileThemeToggle extends StatelessWidget {
  const AuthMobileThemeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppThemeController.instance,
      builder: (context, _) {
        final isDark = AppThemeController.instance.isDarkMode;
        final tooltip = isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode';

        return Tooltip(
          message: tooltip,
          child: Material(
            color: Colors.white.withValues(alpha: 0.14),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: AppThemeController.instance.toggleTheme,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 36,
                height: 36,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, anim) =>
                      ScaleTransition(scale: anim, child: child),
                  child: Icon(
                    isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                    key: ValueKey(isDark),
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Trust line badge at the bottom of the desktop brand panel.
class AuthDesktopTrustLine extends StatelessWidget {
  const AuthDesktopTrustLine({
    super.key,
    this.text = 'Trusted by 10,000+ doctors across India',
    this.accent = AppColors.doctorBlue,
  });

  final String text;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _AuthDesktopAvatarStack(accent: accent),
        const SizedBox(width: 14),
        Flexible(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: 'Inter', 
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.80),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _AuthDesktopAvatarStack extends StatelessWidget {
  const _AuthDesktopAvatarStack({required this.accent});

  final Color accent;

  static const _size = 28.0;
  static const _overlap = 18.0;

  static const _colors = [
    Color(0xFF38BDF8),
    Color(0xFF818CF8),
    Color(0xFF34D399),
  ];

  static const _initials = ['DR', 'MD', 'RN'];

  @override
  Widget build(BuildContext context) {
    final ringColor = Color.lerp(accent, Colors.black, 0.40) ?? accent;

    return SizedBox(
      width: _size + (_colors.length - 1) * _overlap,
      height: _size,
      child: Stack(
        children: [
          for (var i = 0; i < _colors.length; i++)
            Positioned(
              left: i * _overlap,
              child: Container(
                width: _size,
                height: _size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _colors[i],
                  border: Border.all(color: ringColor, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  _initials[i],
                  style: TextStyle(fontFamily: 'Inter', 
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Feature bullet item with interactive hover effect.
class AuthFeatureBulletItem {
  const AuthFeatureBulletItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class AuthDesktopFeatureBullets extends StatelessWidget {
  const AuthDesktopFeatureBullets({
    super.key,
    required this.features,
    this.accent = AppColors.doctorBlue,
  });

  final List<AuthFeatureBulletItem> features;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < features.length; i++) ...[
          _AuthDesktopFeatureBullet(
            icon: features[i].icon,
            label: features[i].label,
            accent: accent,
          ),
          if (i < features.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _AuthDesktopFeatureBullet extends StatefulWidget {
  const _AuthDesktopFeatureBullet({
    required this.icon,
    required this.label,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final Color accent;

  @override
  State<_AuthDesktopFeatureBullet> createState() =>
      _AuthDesktopFeatureBulletState();
}

class _AuthDesktopFeatureBulletState extends State<_AuthDesktopFeatureBullet> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        offset: Offset(_hovered ? 0.02 : 0, 0),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _hovered ? 0.10 : 0.0),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withValues(alpha: _hovered ? 0.18 : 0.0),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: _hovered ? 0.30 : 0.20),
                      Colors.white.withValues(alpha: _hovered ? 0.14 : 0.08),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: Colors.white.withValues(
                      alpha: _hovered ? 0.36 : 0.20,
                    ),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.accent.withValues(
                        alpha: _hovered ? 0.40 : 0.20,
                      ),
                      blurRadius: _hovered ? 18 : 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  widget.icon,
                  size: 19,
                  color: Colors.white.withValues(alpha: 0.95),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Inter', 
                    fontSize: 15.5,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: _hovered ? 1 : 0.88),
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Secure & encrypted sign-in" footer.
class AuthSecureFooter extends StatelessWidget {
  const AuthSecureFooter({
    super.key,
    this.text = 'Secure & encrypted sign-in',
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.verified_user_outlined,
          size: 15,
          color: AppColors.textSecondaryOf(context),
        ),
        const SizedBox(width: 7),
        Text(
          text,
          style: TextStyle(fontFamily: 'Inter', 
            fontSize: AppTypography.labelMedium,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondaryOf(context),
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }
}

/// Smooth staggered fade-and-slide transition.
class AuthFadeSlideIn extends StatefulWidget {
  const AuthFadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.slideDistance = 18.0,
    this.duration = const Duration(milliseconds: 420),
  });

  final Widget child;
  final Duration delay;
  final double slideDistance;
  final Duration duration;

  @override
  State<AuthFadeSlideIn> createState() => _AuthFadeSlideInState();
}

class _AuthFadeSlideInState extends State<AuthFadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) {
        return Opacity(
          opacity: _curve.value,
          child: Transform.translate(
            offset: Offset(
              0,
              (1 - _curve.value) * widget.slideDistance,
            ),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
