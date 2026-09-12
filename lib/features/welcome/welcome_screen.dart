import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/layout/responsive_layout.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/role_card.dart';
import '../../widgets/theme_toggle_button.dart';
import '../auth/doctor_login_screen.dart';
import '../auth/medical_store_login_screen.dart';
import '../auth/patient_login_screen.dart';
import '../auth/lab_login_screen.dart';
import '../ambulance/ambulance_invite_setup_screen.dart';
import '../ambulance/ambulance_login_screen.dart';
import '../../core/invite/pending_ambulance_invite_store.dart';

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
  const WelcomeScreen({super.key});

  List<_WelcomeRoleOption> _roleOptions(BuildContext context) => [
        _WelcomeRoleOption(
          title: 'Doctor',
          subtitle: 'Manage appointments, patients & prescriptions',
          color: AppColors.doctorBlue,
          icon: Icons.medical_services_rounded,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DoctorLoginScreen()),
          ),
        ),
        _WelcomeRoleOption(
          title: 'Patient',
          subtitle: 'Book doctors, labs & track your health',
          color: AppColors.patientTeal,
          icon: Icons.person_rounded,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PatientLoginScreen()),
          ),
        ),
        _WelcomeRoleOption(
          title: 'Pharmacy',
          subtitle: 'Receive and dispense prescriptions',
          color: AppColors.pharmacyGreen,
          icon: Icons.local_pharmacy_rounded,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MedicalStoreLoginScreen()),
          ),
        ),
        _WelcomeRoleOption(
          title: 'Lab',
          subtitle: 'Manage diagnostic test orders',
          color: AppColors.labPurple,
          icon: Icons.biotech_rounded,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LabLoginScreen()),
          ),
        ),
        _WelcomeRoleOption(
          title: 'Ambulance',
          subtitle: 'Handle emergency pickup requests',
          color: const Color(0xFFDC2626),
          icon: Icons.emergency_rounded,
          onTap: () {
            if (PendingAmbulanceInviteStore.hasPending) {
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
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AmbulanceLoginScreen()),
            );
          },
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final roles = _roleOptions(context);
    final isWebDesktop = ResponsiveLayout.isWeb && !ResponsiveLayout.isCompact(context);

    if (isWebDesktop) {
      return _WebWelcomeScaffold(roles: roles);
    }

    return _MobileWelcomeScaffold(roles: roles);
  }
}

/// Split-panel welcome — web / desktop browser only.
class _WebWelcomeScaffold extends StatelessWidget {
  const _WebWelcomeScaffold({required this.roles});

  final List<_WelcomeRoleOption> roles;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Expanded(flex: 40, child: _WebBrandPanel()),
          Expanded(
            flex: 60,
            child: ColoredBox(
              color: AppColors.surfaceOf(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(48, 48, 48, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Select your role',
                              style: GoogleFonts.inter(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimaryOf(context),
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Sign in to the experience built for you',
                              style: GoogleFonts.inter(
                                fontSize: 13.5,
                                color: AppColors.textSecondaryOf(context),
                              ),
                            ),
                          ],
                        ),
                        const ThemeToggleButton(),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Expanded(
                      child: ListView.separated(
                        itemCount: roles.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final role = roles[index];
                          return RoleCard(
                            title: role.title,
                            subtitle: role.subtitle,
                            color: role.color,
                            icon: role.icon,
                            onTap: role.onTap,
                            variant: RoleCardVariant.web,
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 13,
                          color: AppColors.textSecondaryOf(context),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Secure & encrypted sign-in',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                      ],
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
          colors: [
            Color(0xFF064E3B),
            Color(0xFF0F766E),
            Color(0xFF0D9488),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -60,
            right: -40,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Positioned(
            bottom: -70,
            left: -30,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.local_hospital_rounded, color: Colors.white, size: 30),
                ),
                const SizedBox(height: 24),
                Text(
                  'DoctorNect',
                  style: GoogleFonts.inter(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'One platform for every\nhealthcare role',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFFCCFBF1),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 32),
                const _BrandBullet(
                  icon: Icons.people_alt_outlined,
                  text: 'Doctors, patients & care partners',
                ),
                const SizedBox(height: 14),
                const _BrandBullet(
                  icon: Icons.medication_outlined,
                  text: 'Prescriptions, labs & ambulance',
                ),
                const SizedBox(height: 14),
                const _BrandBullet(
                  icon: Icons.hub_outlined,
                  text: 'Connected end-to-end',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandBullet extends StatelessWidget {
  const _BrandBullet({required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: const Color(0xFF5EEAD4)),
            const SizedBox(width: 12),
          ] else ...[
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Color(0xFF5EEAD4),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
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
                                    borderRadius: BorderRadius.circular(compactHeight ? 12 : 15),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
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
                                fontSize: compactHeight ? 18 : 20,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withValues(alpha: 0.92),
                                letterSpacing: -0.2,
                              ),
                            ),
                            SizedBox(height: compactHeight ? 4 : 8),
                            Text(
                              'Welcome',
                              style: GoogleFonts.inter(
                                fontSize: compactHeight ? 26 : 30,
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
                                fontSize: compactHeight ? 13 : 14,
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
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
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
                                padding: EdgeInsets.fromLTRB(20, compactHeight ? 12 : 16, 20, 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Select your role',
                                      style: GoogleFonts.inter(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimaryOf(context),
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Tap a card to sign in',
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        color: AppColors.textSecondaryOf(context),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: ListView(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
                                      if (i < roles.length - 1) const SizedBox(height: 10),
                                    ],
                                    const SizedBox(height: 14),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.verified_user_outlined,
                                          size: 14,
                                          color: AppColors.textSecondaryOf(context).withValues(alpha: 0.8),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Secure & encrypted sign-in',
                                          style: GoogleFonts.inter(
                                            fontSize: 11,
                                            color: AppColors.textSecondaryOf(context),
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
