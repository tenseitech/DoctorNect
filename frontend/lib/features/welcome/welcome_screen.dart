import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/auth/unified_auth_coordinator.dart';
import '../../core/enums/user_type.dart';
import '../../core/invite/pending_ambulance_invite_store.dart';
import '../../core/layout/responsive_layout.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme_controller.dart';
import '../../widgets/role_card.dart';
import '../ambulance/ambulance_invite_setup_screen.dart';
import '../auth/unified_auth_intro_screen.dart';
import '../auth/widgets/auth_brand_components.dart';
import '../onboarding/onboarding_name_screen.dart';

class _WelcomeRoleOption {
  const _WelcomeRoleOption({
    required this.role,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
  });

  final UserType role;
  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;
}

class _RoleBenefitData {
  const _RoleBenefitData({
    required this.icon,
    required this.headline,
    required this.benefits,
  });

  final IconData icon;
  final String headline;
  final List<String> benefits;
}

/// Role selection entry point supporting all 5 healthcare roles:
/// Doctor, Patient, Pharmacy, Lab, Ambulance.
///
/// Features:
/// - Single-column list role cards on both mobile and desktop.
/// - Role-aware dynamic desktop left panel with smooth AnimatedSwitcher transition.
/// - Modern consumer-grade mobile layout with hero accent tint and pinned action bar.
/// - Dynamic `Continue as <Role>` button.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({
    super.key,
    this.verifiedMobile,
    this.verifiedOtp,
    this.isNewUser = false,
  });

  final String? verifiedMobile;
  final String? verifiedOtp;
  final bool isNewUser;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  UserType? _selectedRole;

  void _openUnifiedAuth(BuildContext context, UserType role, Color accent) {
    openUnifiedAuthIntro(context, role: role, accentColor: accent);
  }

  void _handleContinue() {
    final role = _selectedRole;
    if (role == null) return;

    if (widget.isNewUser) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OnboardingNameScreen(
            role: role,
            mobileDigits: widget.verifiedMobile ?? '',
          ),
        ),
      );
      return;
    }

    if (role == UserType.ambulance && PendingAmbulanceInviteStore.hasPending) {
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

    final accent = _roleColor(role);
    _openUnifiedAuth(context, role, accent);
  }

  Color _roleColor(UserType role) => switch (role) {
        UserType.doctor => AppColors.doctorBlue,
        UserType.patient => AppColors.patientTeal,
        UserType.medical => const Color(0xFF0D9488),
        UserType.medicalStore => AppColors.pharmacyGreen,
        UserType.lab => AppColors.labPurple,
        UserType.ambulance => const Color(0xFFDC2626),
        _ => AppColors.doctorBlue,
      };

  List<_WelcomeRoleOption> _roleOptions() => [
        _WelcomeRoleOption(
          role: UserType.doctor,
          title: UnifiedAuthCoordinator.roleLabel(UserType.doctor),
          subtitle: UnifiedAuthCoordinator.roleSubtitle(UserType.doctor),
          color: AppColors.doctorBlue,
          icon: Icons.medical_services_rounded,
        ),
        _WelcomeRoleOption(
          role: UserType.patient,
          title: UnifiedAuthCoordinator.roleLabel(UserType.patient),
          subtitle: UnifiedAuthCoordinator.roleSubtitle(UserType.patient),
          color: AppColors.patientTeal,
          icon: Icons.person_rounded,
        ),
        _WelcomeRoleOption(
          role: UserType.medicalStore,
          title: UnifiedAuthCoordinator.roleLabel(UserType.medicalStore),
          subtitle: UnifiedAuthCoordinator.roleSubtitle(UserType.medicalStore),
          color: AppColors.pharmacyGreen,
          icon: Icons.local_pharmacy_rounded,
        ),
        _WelcomeRoleOption(
          role: UserType.lab,
          title: UnifiedAuthCoordinator.roleLabel(UserType.lab),
          subtitle: UnifiedAuthCoordinator.roleSubtitle(UserType.lab),
          color: AppColors.labPurple,
          icon: Icons.biotech_rounded,
        ),
        _WelcomeRoleOption(
          role: UserType.ambulance,
          title: UnifiedAuthCoordinator.roleLabel(UserType.ambulance),
          subtitle: UnifiedAuthCoordinator.roleSubtitle(UserType.ambulance),
          color: const Color(0xFFDC2626),
          icon: Icons.emergency_rounded,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final roles = _roleOptions();
    final selectedAccent = _selectedRole != null
        ? _roleColor(_selectedRole!)
        : AppColors.doctorBlue;

    return LayoutBuilder(
      builder: (context, constraints) {
        final splitLayout =
            constraints.maxWidth >= ResponsiveLayout.mediumMaxWidth;

        return splitLayout
            ? _WebWelcomeScaffold(
                roles: roles,
                selectedRole: _selectedRole,
                selectedAccent: selectedAccent,
                onSelectRole: (role) => setState(() => _selectedRole = role),
                onContinue: _handleContinue,
              )
            : _MobileWelcomeScaffold(
                roles: roles,
                selectedRole: _selectedRole,
                selectedAccent: selectedAccent,
                onSelectRole: (role) => setState(() => _selectedRole = role),
                onContinue: _handleContinue,
              );
      },
    );
  }
}

/// Desktop / wide layout: 50% dynamic brand panel + 50% centered modern card.
class _WebWelcomeScaffold extends StatelessWidget {
  const _WebWelcomeScaffold({
    required this.roles,
    required this.selectedRole,
    required this.selectedAccent,
    required this.onSelectRole,
    required this.onContinue,
  });

  final List<_WelcomeRoleOption> roles;
  final UserType? selectedRole;
  final Color selectedAccent;
  final ValueChanged<UserType> onSelectRole;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AuthBrandTheme.desktopRightBg,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _WebDynamicBrandPanel(
              selectedRole: selectedRole,
              selectedAccent: selectedAccent,
            ),
          ),
          Expanded(
            child: _WebRolePanel(
              roles: roles,
              selectedRole: selectedRole,
              selectedAccent: selectedAccent,
              onSelectRole: onSelectRole,
              onContinue: onContinue,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dynamic Left Desktop Panel:
/// - Background subtly shifts towards selected role's accent hue.
/// - Role-aware content: AnimatedSwitcher crossfades between default platform info
///   and selected role's headline, glowing accent icon, and 3 check benefit rows.
class _WebDynamicBrandPanel extends StatelessWidget {
  const _WebDynamicBrandPanel({
    required this.selectedRole,
    required this.selectedAccent,
  });

  final UserType? selectedRole;
  final Color selectedAccent;

  static const _roleBenefits = <UserType, _RoleBenefitData>{
    UserType.doctor: _RoleBenefitData(
      icon: Icons.medical_services_rounded,
      headline: 'Run your practice, simply.',
      benefits: [
        'Manage appointments and your schedule',
        'Write and send digital prescriptions',
        'Keep patient records in one place',
      ],
    ),
    UserType.patient: _RoleBenefitData(
      icon: Icons.person_rounded,
      headline: 'Care that comes to you.',
      benefits: [
        'Book doctors and lab tests',
        'Keep your prescriptions and records together',
        'Request an ambulance when it matters',
      ],
    ),
    UserType.medicalStore: _RoleBenefitData(
      icon: Icons.local_pharmacy_rounded,
      headline: 'Fulfil prescriptions faster.',
      benefits: [
        'Receive prescriptions digitally',
        'Manage and dispense orders',
        'Stay connected with doctors and patients',
      ],
    ),
    UserType.lab: _RoleBenefitData(
      icon: Icons.biotech_rounded,
      headline: 'Diagnostics, connected.',
      benefits: [
        'Receive test orders from doctors',
        'Upload and share reports securely',
        'Manage your lab\'s workflow',
      ],
    ),
    UserType.ambulance: _RoleBenefitData(
      icon: Icons.emergency_rounded,
      headline: 'Respond faster.',
      benefits: [
        'Get emergency pickup requests',
        'Manage your trips and availability',
        'Stay connected with patients',
      ],
    ),
  };

  List<Color> _panelGradientColors(UserType? role) {
    if (role == null) {
      return const [
        Color(0xFF031B4E),
        Color(0xFF0A2870),
        Color(0xFF0052CC),
        Color(0xFF02102E),
      ];
    }
    return switch (role) {
      UserType.doctor => const [
          Color(0xFF031B4E),
          Color(0xFF0A2870),
          Color(0xFF0052CC),
          Color(0xFF02102E),
        ],
      UserType.patient => const [
          Color(0xFF021E38),
          Color(0xFF053545),
          Color(0xFF007582),
          Color(0xFF011420),
        ],
      UserType.medicalStore => const [
          Color(0xFF02202C),
          Color(0xFF053A30),
          Color(0xFF007A4D),
          Color(0xFF011616),
        ],
      UserType.lab => const [
          Color(0xFF14113D),
          Color(0xFF221557),
          Color(0xFF5A2096),
          Color(0xFF0D0922),
        ],
      UserType.ambulance => const [
          Color(0xFF2E0B16),
          Color(0xFF480F22),
          Color(0xFF881126),
          Color(0xFF1B040A),
        ],
      _ => const [
          Color(0xFF031B4E),
          Color(0xFF0A2870),
          Color(0xFF0052CC),
          Color(0xFF02102E),
        ],
    };
  }

  @override
  Widget build(BuildContext context) {
    final gradientColors = _panelGradientColors(selectedRole);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
          stops: const [0.0, 0.35, 0.75, 1.0],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Soft radial ambient glow shifting with selected role accent
          AnimatedPositioned(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            left: -80,
            top: -60,
            child: Container(
              width: 520,
              height: 520,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    selectedAccent.withValues(alpha: 0.28),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          const AuthDesktopBrandBackdrop(accent: AppColors.doctorBlue),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tall = constraints.maxHeight >= 720;

                final panel = Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 56,
                    vertical: tall ? 44 : 28,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Top Left: Logo + "DoctorNect" wordmark
                      const AuthFadeSlideIn(
                        delay: Duration.zero,
                        child: AuthDesktopBrandMark(
                          accent: AppColors.doctorBlue,
                          icon: Icons.local_hospital_rounded,
                        ),
                      ),
                      // Center: Role-aware content with AnimatedSwitcher
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 350),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.04),
                              end: Offset.zero,
                            ).animate(anim),
                            child: child,
                          ),
                        ),
                        child: selectedRole != null &&
                                _roleBenefits.containsKey(selectedRole!)
                            ? _buildSelectedRoleContent(
                                _roleBenefits[selectedRole!]!,
                                tall,
                              )
                            : _buildDefaultContent(tall),
                      ),
                      // Bottom: Trust line (kept exactly as it was)
                      const AuthFadeSlideIn(
                        delay: Duration(milliseconds: 250),
                        child: AuthDesktopTrustLine(
                          accent: AppColors.doctorBlue,
                          text: 'Trusted by 10,000+ healthcare providers',
                        ),
                      ),
                    ],
                  ),
                );

                if (constraints.maxHeight >= 620) return panel;

                return SingleChildScrollView(
                  child: SizedBox(height: 620, child: panel),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultContent(bool tall) {
    return Column(
      key: const ValueKey('default_brand_content'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'One platform for every\nhealthcare role',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: tall ? 42 : 36,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: -0.7,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Connect doctors, patients, pharmacies, labs, and ambulances in one seamless healthcare network.',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 16,
            fontWeight: FontWeight.w400,
            color: Colors.white.withValues(alpha: 0.85),
            height: 1.5,
          ),
        ),
        SizedBox(height: tall ? 32 : 22),
        // Simple clean icon + text lines (no heavy pill boxes)
        const _SimpleFeatureRow(
          icon: Icons.people_alt_outlined,
          label: 'Doctors, patients & care partners',
        ),
        const SizedBox(height: 12),
        const _SimpleFeatureRow(
          icon: Icons.medication_outlined,
          label: 'Prescriptions, labs & pharmacy',
        ),
        const SizedBox(height: 12),
        const _SimpleFeatureRow(
          icon: Icons.hub_outlined,
          label: 'Connected end-to-end network',
        ),
      ],
    );
  }

  Widget _buildSelectedRoleContent(_RoleBenefitData data, bool tall) {
    return Column(
      key: ValueKey('role_content_${data.headline}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Large role icon in glowing circle with role accent color
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: selectedAccent.withValues(alpha: 0.20),
            shape: BoxShape.circle,
            border: Border.all(
              color: selectedAccent.withValues(alpha: 0.55),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: selectedAccent.withValues(alpha: 0.40),
                blurRadius: 22,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Center(
            child: Icon(
              data.icon,
              size: 32,
              color: Colors.white,
            ),
          ),
        ),
        SizedBox(height: tall ? 22 : 16),
        Text(
          data.headline,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: tall ? 38 : 32,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: -0.6,
            height: 1.15,
          ),
        ),
        SizedBox(height: tall ? 24 : 18),
        for (final benefit in data.benefits)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: selectedAccent.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selectedAccent.withValues(alpha: 0.65),
                      width: 1.5,
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    benefit,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                      letterSpacing: -0.1,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Clean simple feature line: icon + label (no heavy pill boxes).
class _SimpleFeatureRow extends StatelessWidget {
  const _SimpleFeatureRow({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 20,
          color: Colors.white.withValues(alpha: 0.90),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.92),
              letterSpacing: -0.1,
            ),
          ),
        ),
      ],
    );
  }
}

/// Right desktop panel with centered card holding the 5 list-style role cards.
class _WebRolePanel extends StatelessWidget {
  const _WebRolePanel({
    required this.roles,
    required this.selectedRole,
    required this.selectedAccent,
    required this.onSelectRole,
    required this.onContinue,
  });

  final List<_WelcomeRoleOption> roles;
  final UserType? selectedRole;
  final Color selectedAccent;
  final ValueChanged<UserType> onSelectRole;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [AppColors.darkBackground, AppColors.darkSurface]
              : const [
                  AuthBrandTheme.desktopRightBg,
                  AuthBrandTheme.desktopRightBgTint,
                ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const AuthDesktopAuthBackdrop(accent: AppColors.doctorBlue),
          SafeArea(
            child: Stack(
              children: [
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 36,
                      vertical: 24,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 500),
                      child: AuthFadeSlideIn(
                        delay: const Duration(milliseconds: 100),
                        child: _DesktopRoleSelectionCard(
                          roles: roles,
                          selectedRole: selectedRole,
                          selectedAccent: selectedAccent,
                          onSelectRole: onSelectRole,
                          onContinue: onContinue,
                        ),
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  top: 20,
                  right: 28,
                  child: AuthDesktopThemeToggle(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Elevated floating card holding the 5 single-column list cards.
class _DesktopRoleSelectionCard extends StatelessWidget {
  const _DesktopRoleSelectionCard({
    required this.roles,
    required this.selectedRole,
    required this.selectedAccent,
    required this.onSelectRole,
    required this.onContinue,
  });

  final List<_WelcomeRoleOption> roles;
  final UserType? selectedRole;
  final Color selectedAccent;
  final ValueChanged<UserType> onSelectRole;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final canContinue = selectedRole != null;

    final continueLabel = canContinue
        ? 'Continue as ${UnifiedAuthCoordinator.roleLabel(selectedRole!)}'
        : 'Continue';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? AppColors.borderOf(context)
              : Colors.white.withValues(alpha: 0.90),
        ),
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : const Color(0xFF0F172A))
                .withValues(alpha: isDark ? 0.40 : 0.08),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: selectedAccent.withValues(alpha: isDark ? 0.16 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select your role',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimaryOf(context),
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose your account type to continue',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondaryOf(context),
                  height: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Single-column list of all 5 role cards
          for (var i = 0; i < roles.length; i++) ...[
            RoleCard(
              title: roles[i].title,
              subtitle: roles[i].subtitle,
              color: roles[i].color,
              icon: roles[i].icon,
              onTap: () => onSelectRole(roles[i].role),
              isSelected: selectedRole == roles[i].role,
              variant: RoleCardVariant.web,
            ),
            if (i < roles.length - 1) const SizedBox(height: 10),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 54,
            child: FilledButton(
              onPressed: canContinue ? onContinue : null,
              style: FilledButton.styleFrom(
                backgroundColor: selectedAccent,
                disabledBackgroundColor:
                    isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: canContinue ? 3 : 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    continueLabel,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: canContinue
                          ? Colors.white
                          : (isDark
                              ? const Color(0xFF64748B)
                              : const Color(0xFF94A3B8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: canContinue
                        ? Colors.white
                        : (isDark
                            ? const Color(0xFF64748B)
                            : const Color(0xFF94A3B8)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const AuthSecureFooter(),
        ],
      ),
    );
  }
}

/// Phone / narrow view (< 900px) — modern consumer onboarding design (Uber / Google Pay / Swiggy style).
class _MobileWelcomeScaffold extends StatelessWidget {
  const _MobileWelcomeScaffold({
    required this.roles,
    required this.selectedRole,
    required this.selectedAccent,
    required this.onSelectRole,
    required this.onContinue,
  });

  final List<_WelcomeRoleOption> roles;
  final UserType? selectedRole;
  final Color selectedAccent;
  final ValueChanged<UserType> onSelectRole;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final pageBg =
        isDark ? AppColors.surfaceOf(context) : const Color(0xFFF7F9FC);
    final canContinue = selectedRole != null;

    final continueLabel = canContinue
        ? 'Continue as ${UnifiedAuthCoordinator.roleLabel(selectedRole!)}'
        : 'Continue';

    return Scaffold(
      backgroundColor: pageBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    // Top bar: logo mark (36px rounded square, brand blue, white cross) + "DoctorNect" wordmark on left; icon-only theme toggle on right
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.asset(
                                'assets/images/logo_icon.png',
                                width: 36,
                                height: 36,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.medium,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: AppColors.doctorBlue,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.local_hospital_rounded,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'DoctorNect',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimaryOf(context),
                                letterSpacing: -0.3,
                              ),
                            ),
                          ],
                        ),
                        const _MobileThemeToggle(),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Heading block: "Who are you joining as?" 28px w800, subtext "Pick your role to get started" 15px, 6px below
                    Text(
                      'Who are you joining as?',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimaryOf(context),
                        letterSpacing: -0.6,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Pick your role to get started',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 28),
                    // Role list: 20px horizontal padding, 12px gap between cards, single column
                    for (var i = 0; i < roles.length; i++) ...[
                      _MobileRoleTile(
                        title: roles[i].title,
                        subtitle: roles[i].subtitle,
                        color: roles[i].color,
                        icon: roles[i].icon,
                        isSelected: selectedRole == roles[i].role,
                        onTap: () => onSelectRole(roles[i].role),
                      ),
                      if (i < roles.length - 1) const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            // Bottom bar: pinned, SafeArea bottom, 20px padding, page background, very soft top fade instead of hard divider
            _MobileBottomBar(
              pageBg: pageBg,
              canContinue: canContinue,
              continueLabel: continueLabel,
              selectedAccent: selectedAccent,
              onContinue: onContinue,
            ),
          ],
        ),
      ),
    );
  }
}

/// Private mobile role tile widget.
class _MobileRoleTile extends StatefulWidget {
  const _MobileRoleTile({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_MobileRoleTile> createState() => _MobileRoleTileState();
}

class _MobileRoleTileState extends State<_MobileRoleTile> {
  bool _isPressed = false;

  void _handleTap() {
    HapticFeedback.selectionClick();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);

    // Selected state: accent tint background (about 6% light / 14% dark)
    // Unselected state: surface color
    final bgColor = widget.isSelected
        ? widget.color.withValues(alpha: isDark ? 0.14 : 0.06)
        : AppColors.surfaceOf(context);

    // Border: 1.5px accent border when selected; 1px soft border when unselected
    final borderColor = widget.isSelected
        ? widget.color
        : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0));
    final borderWidth = widget.isSelected ? 1.5 : 1.0;

    // Subtle soft shadow, no heavy shadow
    final boxShadow = widget.isSelected
        ? [
            BoxShadow(
              color: widget.color.withValues(alpha: isDark ? 0.16 : 0.08),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ]
        : [
            BoxShadow(
              color: (isDark ? Colors.black : const Color(0xFF0F172A))
                  .withValues(alpha: isDark ? 0.16 : 0.03),
              blurRadius: 6,
              offset: const Offset(0, 1),
            ),
          ];

    return AnimatedScale(
      scale: _isPressed ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeInOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        constraints: const BoxConstraints(minHeight: 82),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: borderColor,
            width: borderWidth,
          ),
          boxShadow: boxShadow,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _handleTap,
            onTapDown: (_) => setState(() => _isPressed = true),
            onTapUp: (_) => setState(() => _isPressed = false),
            onTapCancel: () => setState(() => _isPressed = false),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Left: 48px icon tile, 14px radius, role-accent tinted background, role-accent icon
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: widget.color.withValues(
                        alpha: isDark ? 0.18 : 0.10,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Icon(
                        widget.icon,
                        size: 24,
                        color: widget.color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Middle: title 16px w600 (primary color), description 13px w400 (secondary color), max 2 lines, wraps normally, NO ellipsis/clipping
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
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimaryOf(context),
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.subtitle,
                          maxLines: 2,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 13,
                            fontWeight: FontWeight.w400,
                            color: AppColors.textSecondaryOf(context),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Right: 24px selection indicator: thin light-grey ring when unselected; filled accent circle with white check when selected
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (child, anim) => ScaleTransition(
                      scale: anim,
                      child: FadeTransition(opacity: anim, child: child),
                    ),
                    child: widget.isSelected
                        ? Container(
                            key: const ValueKey('mobile_selected_check'),
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: widget.color,
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.check_rounded,
                                size: 15,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : Container(
                            key: const ValueKey('mobile_unselected_ring'),
                            width: 24,
                            height: 24,
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
    );
  }
}

/// Pinned bottom bar with very soft top fade, 56px action button, and encrypted sign-in note.
class _MobileBottomBar extends StatelessWidget {
  const _MobileBottomBar({
    required this.pageBg,
    required this.canContinue,
    required this.continueLabel,
    required this.selectedAccent,
    required this.onContinue,
  });

  final Color pageBg;
  final bool canContinue;
  final String continueLabel;
  final Color selectedAccent;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);

    return Container(
      decoration: BoxDecoration(
        color: pageBg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Very soft top fade instead of a hard divider
          Container(
            height: 14,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  pageBg.withValues(alpha: 0.0),
                  pageBg,
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 56,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      decoration: BoxDecoration(
                        color: canContinue
                            ? selectedAccent
                            : (isDark
                                ? const Color(0xFF334155)
                                : const Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: canContinue
                            ? [
                                BoxShadow(
                                  color: selectedAccent.withValues(
                                    alpha: isDark ? 0.35 : 0.28,
                                  ),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : null,
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: canContinue ? onContinue : null,
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 200),
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: canContinue
                                          ? Colors.white
                                          : (isDark
                                              ? const Color(0xFF64748B)
                                              : const Color(0xFF94A3B8)),
                                    ),
                                    child: Text(
                                      continueLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                if (canContinue) ...[
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 14,
                        color: AppColors.textSecondaryOf(context),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Secure & encrypted sign-in',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Icon-only theme toggle button for mobile top bar.
class _MobileThemeToggle extends StatelessWidget {
  const _MobileThemeToggle();

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
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xFF0F172A).withValues(alpha: 0.05),
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
                    isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                    key: ValueKey(isDark),
                    color: AppColors.textPrimaryOf(context),
                    size: 19,
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
