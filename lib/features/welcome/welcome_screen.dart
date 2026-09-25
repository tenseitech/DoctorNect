import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/auth/unified_auth_coordinator.dart';
import '../../core/enums/user_type.dart';
import '../../core/invite/pending_ambulance_invite_store.dart';
import '../../core/layout/responsive_layout.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme_controller.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/role_card.dart';
import '../../widgets/theme_toggle_button.dart';
import '../ambulance/ambulance_invite_setup_screen.dart';
import '../auth/unified_auth_intro_screen.dart';
import '../../core/auth/unified_auth_navigation.dart';

class _WelcomeRoleOption {
  const _WelcomeRoleOption({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    this.verifiedMobile,
    this.verifiedOtp,
    this.isNewUser = false,
  });

  final String? verifiedMobile;
  final String? verifiedOtp;
  final bool isNewUser;

  void _openUnifiedAuth(BuildContext context, UserType role, Color accent) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const UnifiedAuthIntroScreen(),
      ),
    );
  }

  void _onSelectRoleForNewUser(BuildContext context, UserType role) {
    if (role == UserType.superAdmin) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Admin Access'),
          content: const Text(
            'Administrator accounts cannot be self-registered. '
            'Please contact the platform administrator to provision access.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final digits = verifiedMobile;
    if (digits == null || digits.isEmpty) {
      _openUnifiedAuth(context, role, AppColors.doctorBlue);
      return;
    }

    UnifiedAuthNavigation.openRegistrationForm(
      context,
      role: role,
      mobileDigits: digits,
    );
  }

  List<_WelcomeRoleOption> _roleOptions(BuildContext context) => [
        _WelcomeRoleOption(
          title: UnifiedAuthCoordinator.roleLabel(UserType.doctor),
          subtitle: UnifiedAuthCoordinator.roleSubtitle(UserType.doctor),
          color: AppColors.doctorBlue,
          icon: Icons.medical_services_rounded,
          onTap: () => isNewUser
              ? _onSelectRoleForNewUser(context, UserType.doctor)
              : _openUnifiedAuth(context, UserType.doctor, AppColors.doctorBlue),
        ),
        _WelcomeRoleOption(
          title: UnifiedAuthCoordinator.roleLabel(UserType.patient),
          subtitle: UnifiedAuthCoordinator.roleSubtitle(UserType.patient),
          color: AppColors.patientTeal,
          icon: Icons.person_rounded,
          onTap: () => isNewUser
              ? _onSelectRoleForNewUser(context, UserType.patient)
              : _openUnifiedAuth(
                  context, UserType.patient, AppColors.patientTeal),
        ),
        _WelcomeRoleOption(
          title: UnifiedAuthCoordinator.roleLabel(UserType.medicalStore),
          subtitle: UnifiedAuthCoordinator.roleSubtitle(UserType.medicalStore),
          color: AppColors.pharmacyGreen,
          icon: Icons.local_pharmacy_rounded,
          onTap: () => isNewUser
              ? _onSelectRoleForNewUser(context, UserType.medicalStore)
              : _openUnifiedAuth(
                  context, UserType.medicalStore, AppColors.pharmacyGreen),
        ),
        _WelcomeRoleOption(
          title: UnifiedAuthCoordinator.roleLabel(UserType.lab),
          subtitle: UnifiedAuthCoordinator.roleSubtitle(UserType.lab),
          color: AppColors.labPurple,
          icon: Icons.biotech_rounded,
          onTap: () => isNewUser
              ? _onSelectRoleForNewUser(context, UserType.lab)
              : _openUnifiedAuth(context, UserType.lab, AppColors.labPurple),
        ),
        _WelcomeRoleOption(
          title: UnifiedAuthCoordinator.roleLabel(UserType.ambulance),
          subtitle: UnifiedAuthCoordinator.roleSubtitle(UserType.ambulance),
          color: const Color(0xFFDC2626),
          icon: Icons.emergency_rounded,
          onTap: () {
            if (!isNewUser && PendingAmbulanceInviteStore.hasPending) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AmbulanceInviteSetupScreen(
                    inviteId: PendingAmbulanceInviteStore.inviteId!,
                    token: PendingAmbulanceInviteStore.token!,
                  ),
                ),
              );
              return;
            }
            if (isNewUser) {
              _onSelectRoleForNewUser(context, UserType.ambulance);
            } else {
              _openUnifiedAuth(
                  context, UserType.ambulance, const Color(0xFFDC2626));
            }
          },
        ),
        _WelcomeRoleOption(
          title: 'Admin / Super Admin',
          subtitle: 'Platform oversight & verification management',
          color: const Color(0xFF4F46E5),
          icon: Icons.admin_panel_settings_rounded,
          onTap: () => isNewUser
              ? _onSelectRoleForNewUser(context, UserType.superAdmin)
              : _openUnifiedAuth(
                  context, UserType.superAdmin, const Color(0xFF4F46E5)),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    if (!isNewUser) {
      return const UnifiedAuthIntroScreen();
    }

    final roles = _roleOptions(context);
    final isWebDesktop =
        ResponsiveLayout.isWeb && ResponsiveLayout.isExpanded(context);

    if (isWebDesktop) {
      return _WebWelcomeScaffold(roles: roles);
    }

    return _MobileWelcomeScaffold(roles: roles);
  }
}

/// Platform-level teal branding for the desktop welcome left panel.
abstract final class _WebWelcomeBrandTheme {
  static const gradient = [
    Color(0xFF032A22),
    Color(0xFF064E3B),
    Color(0xFF0F766E),
    Color(0xFF14B8A6),
  ];

  static const meshMint = Color(0xFF5EEAD4);
  static const meshEmerald = Color(0xFF10B981);
}

/// Split-panel welcome — web / desktop browser only.
class _WebWelcomeScaffold extends StatelessWidget {
  const _WebWelcomeScaffold({required this.roles});

  final List<_WelcomeRoleOption> roles;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Expanded(flex: 40, child: _WebBrandPanel()),
          Expanded(
            flex: 60,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? const [
                          AppColors.darkBackground,
                          AppColors.darkSurface,
                        ]
                      : const [
                          Color(0xFFF7F9FC),
                          Color(0xFFEEF3FB),
                        ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(48, 48, 48, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _WebWelcomeFadeSlideIn(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Select your role',
                                  style: GoogleFonts.inter(
                                    fontSize: AppTypography.headlineLarge,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimaryOf(context),
                                    letterSpacing: -0.5,
                                    height: 1.15,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Sign in to the experience built for you',
                                  style: GoogleFonts.inter(
                                    fontSize: AppTypography.bodyMedium,
                                    fontWeight: FontWeight.w400,
                                    color: AppColors.textSecondaryOf(context),
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const _WebWelcomeThemeToggle(),
                      ],
                    ),
                    const SizedBox(height: 26),
                    Expanded(
                      child: ListView.separated(
                        itemCount: roles.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final role = roles[index];
                          return _WebWelcomeFadeSlideIn(
                            delay: Duration(milliseconds: 90 + index * 70),
                            child: RoleCard(
                              title: role.title,
                              subtitle: role.subtitle,
                              color: role.color,
                              icon: role.icon,
                              onTap: role.onTap,
                              variant: RoleCardVariant.web,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    _WebWelcomeFadeSlideIn(
                      delay: const Duration(milliseconds: 480),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 14,
                            color: AppColors.textSecondaryOf(context),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            'Secure & encrypted sign-in',
                            style: GoogleFonts.inter(
                              fontSize: AppTypography.labelMedium,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondaryOf(context),
                              letterSpacing: 0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WebBrandPanel extends StatelessWidget {
  const _WebBrandPanel();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _WebWelcomeBrandTheme.gradient,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const _WebWelcomeBrandBackdrop(),
          Positioned(
            right: -80,
            bottom: -60,
            child: Opacity(
              opacity: 0.16,
              child: _WebWelcomeNetworkGraphic(size: 320),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _WebWelcomeFadeSlideIn(
                  child: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.22),
                          Colors.white.withValues(alpha: 0.10),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.32),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _WebWelcomeBrandTheme.meshMint
                              .withValues(alpha: 0.25),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.local_hospital_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _WebWelcomeFadeSlideIn(
                  delay: const Duration(milliseconds: 80),
                  child: Text(
                    'DoctorNect',
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.displayLarge,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.6,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _WebWelcomeFadeSlideIn(
                  delay: const Duration(milliseconds: 140),
                  child: Text(
                    'One platform for every\nhealthcare role',
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.headlineSmall,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFFCCFBF1),
                      height: 1.45,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                _WebWelcomeFadeSlideIn(
                  delay: const Duration(milliseconds: 210),
                  child: const _WebBrandBullet(
                    icon: Icons.people_alt_outlined,
                    text: 'Doctors, patients & care partners',
                  ),
                ),
                const SizedBox(height: 14),
                _WebWelcomeFadeSlideIn(
                  delay: const Duration(milliseconds: 270),
                  child: const _WebBrandBullet(
                    icon: Icons.medication_outlined,
                    text: 'Prescriptions, labs & ambulance',
                  ),
                ),
                const SizedBox(height: 14),
                _WebWelcomeFadeSlideIn(
                  delay: const Duration(milliseconds: 330),
                  child: const _WebBrandBullet(
                    icon: Icons.hub_outlined,
                    text: 'Connected end-to-end',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WebWelcomeBrandBackdrop extends StatelessWidget {
  const _WebWelcomeBrandBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -180,
            left: -140,
            child: _WebWelcomeSoftGlow(
              diameter: 560,
              color: _WebWelcomeBrandTheme.meshEmerald.withValues(alpha: 0.50),
            ),
          ),
          Positioned(
            top: -120,
            right: -160,
            child: _WebWelcomeSoftGlow(
              diameter: 480,
              color: _WebWelcomeBrandTheme.meshMint.withValues(alpha: 0.28),
            ),
          ),
          Positioned(
            bottom: -220,
            left: -100,
            child: _WebWelcomeSoftGlow(
              diameter: 520,
              color: _WebWelcomeBrandTheme.meshEmerald.withValues(alpha: 0.32),
            ),
          ),
          Positioned(
            bottom: -160,
            right: -80,
            child: _WebWelcomeSoftGlow(
              diameter: 400,
              color: Colors.white.withValues(alpha: 0.10),
            ),
          ),
          Opacity(
            opacity: 0.50,
            child: CustomPaint(painter: _WebWelcomeDotLatticePainter()),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  const Color(0xFF021A15).withValues(alpha: 0.30),
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

class _WebWelcomeSoftGlow extends StatelessWidget {
  const _WebWelcomeSoftGlow({required this.diameter, required this.color});

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

class _WebWelcomeDotLatticePainter extends CustomPainter {
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
  bool shouldRepaint(_WebWelcomeDotLatticePainter oldDelegate) => false;
}

class _WebWelcomeNetworkGraphic extends StatelessWidget {
  const _WebWelcomeNetworkGraphic({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: const _WebWelcomeNetworkGraphicPainter(),
        ),
      ),
    );
  }
}

class _WebWelcomeNetworkGraphicPainter extends CustomPainter {
  const _WebWelcomeNetworkGraphicPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * 0.52, size.height * 0.48);
    final nodePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withValues(alpha: 0.14)
      ..strokeWidth = 1.4;

    final nodes = [
      Offset(size.width * 0.18, size.height * 0.22),
      Offset(size.width * 0.78, size.height * 0.18),
      Offset(size.width * 0.86, size.height * 0.62),
      Offset(size.width * 0.42, size.height * 0.82),
      Offset(size.width * 0.12, size.height * 0.58),
      center,
    ];

    for (var i = 0; i < nodes.length; i++) {
      for (var j = i + 1; j < nodes.length; j++) {
        canvas.drawLine(nodes[i], nodes[j], nodePaint);
      }
    }

    final hubPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white.withValues(alpha: 0.10);
    final hubRing = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = 1.5;

    for (final node in nodes) {
      canvas.drawCircle(node, 7, hubPaint);
      canvas.drawCircle(node, 7, hubRing);
    }

    canvas.drawCircle(center, 16, hubRing);
    canvas.drawCircle(center, 10, hubPaint);
  }

  @override
  bool shouldRepaint(_WebWelcomeNetworkGraphicPainter oldDelegate) => false;
}

class _WebBrandBullet extends StatefulWidget {
  const _WebBrandBullet({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  State<_WebBrandBullet> createState() => _WebBrandBulletState();
}

class _WebBrandBulletState extends State<_WebBrandBullet> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        offset: Offset(_hovered ? 0.015 : 0, 0),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _hovered ? 0.16 : 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: _hovered ? 0.32 : 0.22),
            ),
            boxShadow: [
              BoxShadow(
                color: _WebWelcomeBrandTheme.meshMint
                    .withValues(alpha: _hovered ? 0.22 : 0.10),
                blurRadius: _hovered ? 20 : 12,
                offset: Offset(0, _hovered ? 6 : 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 20,
                color: _WebWelcomeBrandTheme.meshMint,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  widget.text,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.bodyMedium,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: _hovered ? 1 : 0.94),
                    height: 1.3,
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

/// Icon-only theme toggle — matches the desktop auth intro screen.
class _WebWelcomeThemeToggle extends StatelessWidget {
  const _WebWelcomeThemeToggle();

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
                  transitionBuilder: (child, anim) => ScaleTransition(
                    scale: anim,
                    child: child,
                  ),
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

class _WebWelcomeFadeSlideIn extends StatefulWidget {
  const _WebWelcomeFadeSlideIn({
    required this.child,
    this.delay = Duration.zero,
  });

  final Widget child;
  final Duration delay;

  static const _slideDistance = 18.0;

  @override
  State<_WebWelcomeFadeSlideIn> createState() => _WebWelcomeFadeSlideInState();
}

class _WebWelcomeFadeSlideInState extends State<_WebWelcomeFadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
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
              (1 - _curve.value) * _WebWelcomeFadeSlideIn._slideDistance,
            ),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Phone / narrow view — native app + narrow browser.
class _MobileWelcomeScaffold extends StatelessWidget {
  const _MobileWelcomeScaffold({required this.roles});

  final List<_WelcomeRoleOption> roles;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0B5D4B),
              Color(0xFF0F6E56),
              Color(0xFF12836A),
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -50,
              right: -30,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceOf(context).withValues(alpha: 0.06),
                ),
              ),
            ),
            Positioned(
              bottom: 120,
              left: -40,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surfaceOf(context).withValues(alpha: 0.05),
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final screenHeight = constraints.maxHeight;
                  final compactHeight = screenHeight < 640;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          22,
                          compactHeight ? 8 : 16,
                          22,
                          compactHeight ? 10 : 16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  width: compactHeight ? 44 : 52,
                                  height: compactHeight ? 44 : 52,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(
                                        compactHeight ? 12 : 15),
                                    border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.22)),
                                  ),
                                  child: Icon(
                                    Icons.local_hospital_rounded,
                                    color: Colors.white,
                                    size: compactHeight ? 24 : 28,
                                  ),
                                ),
                                const ThemeToggleButton(color: Colors.white),
                              ],
                            ),
                            SizedBox(height: compactHeight ? 10 : 16),
                            Text(
                              'DoctorNect',
                              style: GoogleFonts.inter(
                                fontSize: compactHeight
                                    ? AppTypography.titleMedium
                                    : AppTypography.headlineMedium,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withValues(alpha: 0.92),
                                letterSpacing: -0.2,
                              ),
                            ),
                            SizedBox(height: compactHeight ? 4 : 8),
                            Text(
                              'Welcome',
                              style: GoogleFonts.inter(
                                fontSize: AppTypography.headlineLarge,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.5,
                                height: 1.1,
                              ),
                            ),
                            SizedBox(height: compactHeight ? 4 : 6),
                            Text(
                              'Choose your role to continue',
                              style: GoogleFonts.inter(
                                fontSize: compactHeight
                                    ? AppTypography.bodySmall
                                    : AppTypography.bodyMedium,
                                color: Colors.white.withValues(alpha: 0.85),
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(26)),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x26000000),
                                blurRadius: 20,
                                offset: Offset(0, -4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 10),
                              Center(
                                child: Container(
                                  width: 38,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: AppColors.borderOf(context),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: EdgeInsets.fromLTRB(
                                    20, compactHeight ? 12 : 16, 20, 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Select your role',
                                      style: GoogleFonts.inter(
                                        fontSize: AppTypography.headlineMedium,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimaryOf(context),
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Tap a card to sign in',
                                      style: GoogleFonts.inter(
                                        fontSize: AppTypography.bodySmall,
                                        color:
                                            AppColors.textSecondaryOf(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: ListView(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                  children: [
                                    for (var i = 0; i < roles.length; i++) ...[
                                      RoleCard(
                                        title: roles[i].title,
                                        subtitle: roles[i].subtitle,
                                        color: roles[i].color,
                                        icon: roles[i].icon,
                                        onTap: roles[i].onTap,
                                        variant: RoleCardVariant.mobile,
                                      ),
                                      if (i < roles.length - 1)
                                        const SizedBox(height: 10),
                                    ],
                                    const SizedBox(height: 14),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.verified_user_outlined,
                                          size: 14,
                                          color:
                                              AppColors.textSecondaryOf(context)
                                                  .withValues(alpha: 0.8),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Secure & encrypted sign-in',
                                          style: GoogleFonts.inter(
                                            fontSize: AppTypography.labelSmall,
                                            color: AppColors.textSecondaryOf(
                                                context),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
