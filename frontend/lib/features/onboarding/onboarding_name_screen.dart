import 'package:flutter/material.dart';

import '../../core/auth/onboarding_service.dart';
import '../../core/auth/unified_auth_coordinator.dart';
import '../../core/enums/user_type.dart';
import '../../core/layout/responsive_layout.dart';
import '../../core/notifications/app_toast.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/validators/name_validator.dart';
import '../auth/widgets/auth_brand_components.dart';
import '../dashboard/dashboard_shell.dart';

/// Full Name capture step during onboarding for ALL 6 roles.
///
/// Guarantees:
/// - Validation: Required, trimmed, not only spaces, min 2 chars, no fake role names.
/// - Continue button is disabled until valid.
/// - Shows loading state during save.
/// - Never navigates to a dashboard before role and real name are securely saved.
class OnboardingNameScreen extends StatefulWidget {
  const OnboardingNameScreen({
    super.key,
    required this.role,
    required this.mobileDigits,
  });

  final UserType role;
  final String mobileDigits;

  @override
  State<OnboardingNameScreen> createState() => _OnboardingNameScreenState();
}

class _OnboardingNameScreenState extends State<OnboardingNameScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _saving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _controller.text;
    if (text.trim().isNotEmpty) {
      final error = NameValidator.validate(text);
      if (error != _errorText) {
        setState(() => _errorText = error);
      }
    } else if (_errorText != null) {
      setState(() => _errorText = null);
    } else {
      setState(() {});
    }
  }

  bool get _canSubmit => !_saving && NameValidator.isValid(_controller.text);

  Future<void> _submit() async {
    final name = _controller.text.trim();
    final error = NameValidator.validate(name);
    if (error != null) {
      setState(() => _errorText = error);
      return;
    }

    setState(() {
      _saving = true;
      _errorText = null;
    });

    try {
      await OnboardingService.instance.completeNameOnboarding(
        role: widget.role,
        fullName: name,
        mobileDigits: widget.mobileDigits,
      );

      if (!mounted) return;

      AppToast.success(context, 'Welcome to DoctorNect, $name!');

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => DashboardShell(userType: widget.role),
        ),
        (_) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorText = e.toString().replaceAll('Exception: ', '');
      });
      AppToast.error(
          context, _errorText ?? 'Failed to save profile. Try again.');
    }
  }

  Color get _roleAccent => switch (widget.role) {
        UserType.doctor => AppColors.doctorBlue,
        UserType.patient => AppColors.patientTeal,
        UserType.medical => const Color(0xFF0D9488),
        UserType.medicalStore => AppColors.pharmacyGreen,
        UserType.lab => AppColors.labPurple,
        UserType.ambulance => const Color(0xFFDC2626),
        UserType.superAdmin => AppColors.doctorBlue,
      };

  IconData get _roleIcon => switch (widget.role) {
        UserType.doctor => Icons.medical_services_rounded,
        UserType.patient => Icons.person_rounded,
        UserType.medical => Icons.health_and_safety_rounded,
        UserType.medicalStore => Icons.local_pharmacy_rounded,
        UserType.lab => Icons.biotech_rounded,
        UserType.ambulance => Icons.emergency_rounded,
        UserType.superAdmin => Icons.admin_panel_settings_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= ResponsiveLayout.mediumMaxWidth;
        return wide ? _buildDesktopLayout() : _buildMobileLayout();
      },
    );
  }

  Widget _buildDesktopLayout() {
    final isDark = AppColors.isDark(context);

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AuthBrandTheme.desktopRightBg,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Expanded(child: _DesktopBrandHeroPanel()),
          Expanded(
            child: DecoratedBox(
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
                                child: _buildFormCard(isDark),
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    final screenWidth = MediaQuery.sizeOf(context).width;

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
            SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        AuthMobileBrandWordmark(),
                        AuthMobileThemeToggle(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(AuthBrandTheme.sheetRadius),
                        ),
                        boxShadow: AuthBrandTheme.mobileSheetShadows(context),
                      ),
                      child: SafeArea(
                        top: false,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                          child: _buildFormCard(AppColors.isDark(context)),
                        ),
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

  Widget _buildFormCard(bool isDark) {
    final roleLabel = UnifiedAuthCoordinator.roleLabel(widget.role);

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
          accent: _roleAccent,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(32, 32, 32, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Role chip header
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _roleAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _roleAccent.withValues(alpha: 0.30),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_roleIcon, size: 16, color: _roleAccent),
                    const SizedBox(width: 6),
                    Text(
                      '$roleLabel Account',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _roleAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'What is your full name?',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: AppTypography.headlineMedium,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimaryOf(context),
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Enter your real name to complete registration. Generic role placeholders are not accepted.',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: AppTypography.bodyMedium,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondaryOf(context),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 28),

          // Name Input field
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimaryOf(context),
            ),
            decoration: InputDecoration(
              labelText: 'Full Name',
              hintText: 'e.g. Rahul Sharma',
              prefixIcon: const Icon(Icons.person_outline_rounded),
              errorText: _errorText,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _roleAccent, width: 2),
              ),
            ),
            onSubmitted: (_) {
              if (_canSubmit) _submit();
            },
          ),
          const SizedBox(height: 24),

          // Continue Button
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _canSubmit ? _submit : null,
              style: FilledButton.styleFrom(
                backgroundColor: _roleAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                disabledBackgroundColor: _roleAccent.withValues(alpha: 0.35),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      'Continue',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 24),
          const AuthSecureFooter(),
        ],
      ),
    );
  }
}

class _DesktopBrandHeroPanel extends StatelessWidget {
  const _DesktopBrandHeroPanel();

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
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const AuthDesktopBrandMark(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Set up your\nDoctorNect profile',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.6,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Connect with care partners, verified clinical tools, and patient records across India.',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 16,
                          color: Colors.white.withValues(alpha: 0.82),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                  const AuthDesktopTrustLine(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
