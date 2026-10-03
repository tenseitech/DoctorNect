import 'package:flutter/material.dart';

import '../../core/auth/unified_auth_coordinator.dart';
import '../../core/enums/user_type.dart';
import '../../core/invite/pending_ambulance_invite_store.dart';
import '../../core/layout/responsive_layout.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
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

/// Role selection entry point supporting all 6 healthcare roles:
/// Doctor, Patient, Medical, Pharmacy, Lab, Ambulance.
///
/// Features:
/// - Continue button is disabled until a role is selected.
/// - Visually aligned with [UnifiedAuthIntroScreen] (navy-blue brand identity,
///   50/50 desktop split, floating elevated cards, identical typography, theme
///   toggle, and secure footer).
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
          role: UserType.medical,
          title: UnifiedAuthCoordinator.roleLabel(UserType.medical),
          subtitle: UnifiedAuthCoordinator.roleSubtitle(UserType.medical),
          color: const Color(0xFF0D9488),
          icon: Icons.medical_information_rounded,
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

/// Desktop / wide layout: 50% brand panel + 50% card container.
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
      backgroundColor: isDark
          ? AppColors.darkBackground
          : AuthBrandTheme.desktopRightBg,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Expanded(child: _WebBrandPanel()),
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

/// Left desktop panel with signature Navy-Blue gradient, backdrop, rings, and trust line.
class _WebBrandPanel extends StatelessWidget {
  const _WebBrandPanel();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AuthBrandTheme.desktopBrandGradient,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const AuthDesktopBrandBackdrop(accent: AppColors.doctorBlue),
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final graphicSize = (constraints.maxWidth * 0.56).clamp(
                  230.0,
                  430.0,
                );

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      right: -graphicSize * 0.16,
                      bottom: -graphicSize * 0.14,
                      child: AuthBrandGraphic(size: graphicSize),
                    ),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tall = constraints.maxHeight >= 720;

                final panel = Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 56,
                    vertical: tall ? 48 : 32,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const AuthFadeSlideIn(
                        delay: Duration.zero,
                        child: AuthDesktopBrandMark(
                          accent: AppColors.doctorBlue,
                          icon: Icons.local_hospital_rounded,
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AuthFadeSlideIn(
                            delay: const Duration(milliseconds: 90),
                            child: Text(
                              'One platform for every\nhealthcare role',
                              style: TextStyle(fontFamily: 'Inter', 
                                fontSize: tall ? 42 : 36,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: -0.6,
                                height: 1.15,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          AuthFadeSlideIn(
                            delay: const Duration(milliseconds: 150),
                            child: Text(
                              'Connect doctors, patients, medical facilities, pharmacies, labs, and ambulances in one seamless healthcare network.',
                              style: TextStyle(fontFamily: 'Inter', 
                                fontSize: 16,
                                fontWeight: FontWeight.w400,
                                color: Colors.white.withValues(alpha: 0.82),
                                height: 1.5,
                              ),
                            ),
                          ),
                          SizedBox(height: tall ? 36 : 26),
                          const AuthFadeSlideIn(
                            delay: Duration(milliseconds: 220),
                            child: AuthDesktopFeatureBullets(
                              accent: AppColors.doctorBlue,
                              features: [
                                AuthFeatureBulletItem(
                                  icon: Icons.people_alt_outlined,
                                  label: 'Doctors, patients & care partners',
                                ),
                                AuthFeatureBulletItem(
                                  icon: Icons.medication_outlined,
                                  label: 'Prescriptions, labs & pharmacy',
                                ),
                                AuthFeatureBulletItem(
                                  icon: Icons.hub_outlined,
                                  label: 'Connected end-to-end',
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const AuthFadeSlideIn(
                        delay: Duration(milliseconds: 300),
                        child: AuthDesktopTrustLine(
                          accent: AppColors.doctorBlue,
                          text: 'Trusted by 10,000+ healthcare providers',
                        ),
                      ),
                    ],
                  ),
                );

                if (constraints.maxHeight >= 600) return panel;

                return SingleChildScrollView(
                  child: SizedBox(height: 600, child: panel),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Right desktop panel with centered floating card and top-right theme toggle.
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
                      horizontal: 40,
                      vertical: 40,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
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

/// Elevated floating card holding the role cards, matching [_DesktopAuthCard].
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

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(AuthBrandTheme.desktopCardRadius),
        border: Border.all(
          color: isDark
              ? AppColors.borderOf(context)
              : Colors.white.withValues(alpha: 0.90),
        ),
        boxShadow: AuthBrandTheme.desktopCardShadows(
          context,
          accent: selectedAccent,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(36, 36, 36, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select your role',
                style: TextStyle(fontFamily: 'Inter', 
                  fontSize: AppTypography.headlineMedium,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimaryOf(context),
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose your account type to continue',
                style: TextStyle(fontFamily: 'Inter', 
                  fontSize: AppTypography.bodyMedium,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondaryOf(context),
                  height: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          for (var i = 0; i < roles.length; i++) ...[
            AuthFadeSlideIn(
              delay: Duration(milliseconds: 140 + i * 40),
              child: RoleCard(
                title: roles[i].title,
                subtitle: roles[i].subtitle,
                color: roles[i].color,
                icon: roles[i].icon,
                onTap: () => onSelectRole(roles[i].role),
                isSelected: selectedRole == roles[i].role,
                variant: RoleCardVariant.web,
              ),
            ),
            if (i < roles.length - 1) const SizedBox(height: 10),
          ],
          const SizedBox(height: 24),
          AuthFadeSlideIn(
            delay: const Duration(milliseconds: 400),
            child: SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: canContinue ? onContinue : null,
                style: FilledButton.styleFrom(
                  backgroundColor: selectedAccent,
                  disabledBackgroundColor: isDark
                      ? const Color(0xFF1E293B)
                      : const Color(0xFFE2E8F0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: canContinue ? 2 : 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Continue',
                      style: TextStyle(fontFamily: 'Inter', 
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
          ),
          const SizedBox(height: 20),
          const AuthFadeSlideIn(
            delay: Duration(milliseconds: 450),
            child: AuthSecureFooter(),
          ),
        ],
      ),
    );
  }
}

/// Phone / narrow view — matches [_MobileAuthView] structure.
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
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final compactHeight = screenHeight < 680;
    final graphicSize = (screenWidth * 0.58).clamp(165.0, 250.0);
    final canContinue = selectedRole != null;

    return Scaffold(
      backgroundColor: AuthBrandTheme.mobileHeroGradient.first,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AuthBrandTheme.mobileHeroGradient,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AuthMobileBrandBackdrop(
              width: screenWidth,
              accent: AppColors.doctorBlue,
            ),
            Positioned(
              right: -graphicSize * 0.36,
              top: screenHeight * 0.04,
              child: Opacity(
                opacity: isDark ? 0.60 : 0.85,
                child: AuthBrandGraphic(size: graphicSize),
              ),
            ),
            SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Icon(
                            Icons.local_hospital_rounded,
                            size: 20,
                            color: AppColors.doctorBlue,
                          ),
                        ),
                        const AuthMobileThemeToggle(),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      AuthBrandTheme.mobileHorizontalPadding,
                      compactHeight ? 10 : 16,
                      AuthBrandTheme.mobileHorizontalPadding,
                      0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const AuthMobileBrandWordmark(),
                        const SizedBox(height: 6),
                        Text(
                          'Welcome',
                          style: TextStyle(fontFamily: 'Inter', 
                            fontSize: compactHeight ? 24 : 28,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.5,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Choose your role to continue',
                          style: TextStyle(fontFamily: 'Inter', 
                            fontSize: AppTypography.bodySmall,
                            color: Colors.white.withValues(alpha: 0.85),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: compactHeight ? 12 : 20),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(AuthBrandTheme.sheetRadius),
                        ),
                        boxShadow: AuthBrandTheme.mobileSheetShadows(context),
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
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Select your role',
                                  style: TextStyle(fontFamily: 'Inter', 
                                    fontSize: AppTypography.titleLarge,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimaryOf(context),
                                    letterSpacing: -0.2,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Select a role and tap Continue',
                                  style: TextStyle(fontFamily: 'Inter', 
                                    fontSize: AppTypography.bodySmall,
                                    color: AppColors.textSecondaryOf(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                              itemCount: roles.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, i) => RoleCard(
                                title: roles[i].title,
                                subtitle: roles[i].subtitle,
                                color: roles[i].color,
                                icon: roles[i].icon,
                                onTap: () => onSelectRole(roles[i].role),
                                isSelected: selectedRole == roles[i].role,
                                variant: RoleCardVariant.mobile,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: SizedBox(
                              height: 48,
                              child: FilledButton(
                                onPressed: canContinue ? onContinue : null,
                                style: FilledButton.styleFrom(
                                  backgroundColor: selectedAccent,
                                  disabledBackgroundColor: isDark
                                      ? const Color(0xFF1E293B)
                                      : const Color(0xFFE2E8F0),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: canContinue ? 2 : 0,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Continue',
                                      style: TextStyle(fontFamily: 'Inter', 
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
                          ),
                          const Padding(
                            padding: EdgeInsets.only(bottom: 14),
                            child: AuthSecureFooter(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
