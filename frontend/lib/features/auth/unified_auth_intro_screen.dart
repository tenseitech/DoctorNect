import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/enums/user_type.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme_controller.dart';
import '../../core/utils/asset_resolver.dart';
import '../../widgets/medibond_logo.dart';
import '../patient/profile/support/help_support_screen.dart';
import 'unified_auth_expand_route.dart';
import 'unified_mobile_auth_screen.dart';
import 'widgets/auth_layout.dart';
import 'widgets/unified_auth_mobile_field.dart';

/// Single entry function for navigating to the welcome intro screen.
void openUnifiedAuthIntro(
  BuildContext context, {
  UserType? role,
  Color? accentColor,
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => UnifiedAuthIntroScreen(
        role: role,
        accentColor: accentColor,
      ),
    ),
  );
}

/// Data model for carousel slides.
class WelcomeSlideData {
  const WelcomeSlideData({
    required this.tagline,
    required this.imageAsset,
    this.fallbackIcon = Icons.medical_services_outlined,
  });

  final String tagline;
  final String imageAsset;
  final IconData fallbackIcon;
}

/// Screen 1 — Welcome screen inspired by Practo-style flow.
///
/// Features:
/// - Full-bleed navy/teal gradient background (DoctorNect brand palette)
/// - DoctorNect logo at top
/// - Auto-advancing PageView carousel of 4 healthcare slides with dot indicators
/// - White/dark-mode rounded-top bottom sheet with "Let's get started!"
/// - Read-only styled (+91 | Mobile number) field tapping through to Screen 2
/// - "Trouble signing in?" text link opening a quick help bottom sheet
/// - Responsive: centered in max-width 420px card on large web/desktop screens
class UnifiedAuthIntroScreen extends StatefulWidget {
  const UnifiedAuthIntroScreen({
    super.key,
    this.role,
    this.accentColor,
  });

  final UserType? role;
  final Color? accentColor;

  @override
  State<UnifiedAuthIntroScreen> createState() => _UnifiedAuthIntroScreenState();
}

class _UnifiedAuthIntroScreenState extends State<UnifiedAuthIntroScreen> {
  final _pageController = PageController();
  final _readOnlyMobileController = TextEditingController();

  int _currentSlide = 0;
  Timer? _carouselTimer;
  bool _isNavigating = false;

  static const List<WelcomeSlideData> _slides = [
    WelcomeSlideData(
      tagline: 'Instant walk-in and clinic appointment booking',
      imageAsset: 'assets/images/intro_slide_1.webp',
      fallbackIcon: Icons.calendar_month_rounded,
    ),
    WelcomeSlideData(
      tagline: 'Find and consult trusted doctors near you',
      imageAsset: 'assets/images/intro_slide_2.webp',
      fallbackIcon: Icons.person_search_rounded,
    ),
    WelcomeSlideData(
      tagline: 'Diagnostic labs, pharmacy & ambulance in\u00A0one\u00A0app',
      imageAsset: 'assets/images/intro_slide_3.webp',
      fallbackIcon: Icons.local_hospital_rounded,
    ),
    WelcomeSlideData(
      tagline: 'Your complete digital health records, in one secure place',
      imageAsset: 'assets/images/intro_slide_4.webp',
      fallbackIcon: Icons.folder_shared_rounded,
    ),
  ];

  Color get _accent =>
      widget.accentColor ??
      (widget.role == UserType.doctor
          ? AppColors.doctorBlue
          : AppColors.patientTeal);

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _pageController.dispose();
    _readOnlyMobileController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _carouselTimer?.cancel();
    _carouselTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_pageController.hasClients) return;
      final next = (_currentSlide + 1) % _slides.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  void _onPageChanged(int index) {
    if (_currentSlide != index && mounted) {
      setState(() => _currentSlide = index);
    }
  }

  Future<void> _openMobileScreen() async {
    if (_isNavigating || !mounted) return;
    _isNavigating = true;

    await Navigator.of(context).push<void>(
      UnifiedAuthExpandRoute<void>(
        screen: UnifiedMobileAuthScreen(
          role: widget.role,
          accentColor: _accent,
          focusMobileAfterTransition: true,
        ),
      ),
    );

    if (mounted) _isNavigating = false;
  }

  void _openTroubleSigningInHelp() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _WelcomeHelpBottomSheet(
        onOpenSupport: () {
          Navigator.pop(ctx);
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const HelpSupportScreen()),
          );
        },
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final isDark = AppColors.isDark(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const DoctorNectLogo(
            size: 38,
            transparent: true,
            softGlow: true,
          ),
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              color: Colors.white.withValues(alpha: 0.85),
              size: 22,
            ),
            tooltip: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            onPressed: () => AppThemeController.instance.toggleTheme(),
          ),
        ],
      ),
    );
  }

  Widget _buildCarousel() {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification) {
          _carouselTimer?.cancel();
        } else if (notification is ScrollEndNotification) {
          _startTimer();
        }
        return false;
      },
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              itemCount: _slides.length,
              itemBuilder: (context, index) {
                final slide = _slides[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Container(
                          constraints: const BoxConstraints(
                            maxHeight: 180,
                            maxWidth: 240,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.asset(
                              AssetResolver.resolve(slide.imageAsset),
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  slide.fallbackIcon,
                                  size: 56,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        constraints: const BoxConstraints(maxWidth: 290),
                        child: Text(
                          slide.tagline,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            height: 1.35,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          _buildDotIndicators(),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  Widget _buildDotIndicators() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_slides.length, (index) {
        final active = index == _currentSlide;
        return GestureDetector(
          onTap: () {
            _pageController.animateToPage(
              index,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeInOutCubic,
            );
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: active ? 22 : 6,
            height: 6,
            decoration: BoxDecoration(
              color:
                  active ? Colors.white : Colors.white.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildBottomActionSheet(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            16 + (bottomPadding > 0 ? 0 : 8),
          ),
          child: UnifiedAuthLoginForm(
            mobileController: _readOnlyMobileController,
            accentColor: _accent,
            onTapMobileField: _openMobileScreen,
            onContinue: _openMobileScreen,
            onTroubleSigningIn: _openTroubleSigningInHelp,
            isDesktop: false,
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopCarousel() {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification) {
          _carouselTimer?.cancel();
        } else if (notification is ScrollEndNotification) {
          _startTimer();
        }
        return false;
      },
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              itemCount: _slides.length,
              itemBuilder: (context, index) {
                final slide = _slides[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxHeight: 280,
                            maxWidth: 340,
                          ),
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Image.asset(
                                AssetResolver.resolve(slide.imageAsset),
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 140,
                                  height: 140,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    slide.fallbackIcon,
                                    size: 64,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          slide.tagline,
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            height: 1.3,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          _buildDotIndicators(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    final isDark = AppColors.isDark(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // LEFT PANEL (~43%): dark-teal gradient, logo + toggle, large carousel
          Expanded(
            flex: kAuthLeftPanelFlex,
            child: Container(
              constraints:
                  const BoxConstraints(minWidth: kAuthLeftPanelMinWidth),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF071B2F), // Deep brand Navy
                    Color(0xFF0A2D48),
                    Color(0xFF0C5662),
                    Color(0xFF0D9488), // DoctorNect Teal
                  ],
                  stops: [0.0, 0.35, 0.70, 1.0],
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: [
                    // Top bar of left panel: Logo (left) and Theme Toggle (right, ~24px from edge)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(32, 20, 24, 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const DoctorNectLogo(
                                size: 40,
                                transparent: true,
                                softGlow: true,
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'DoctorNect',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: Icon(
                              isDark
                                  ? Icons.light_mode_outlined
                                  : Icons.dark_mode_outlined,
                              color: Colors.white.withValues(alpha: 0.85),
                              size: 22,
                            ),
                            tooltip: isDark
                                ? 'Switch to Light Mode'
                                : 'Switch to Dark Mode',
                            onPressed: () =>
                                AppThemeController.instance.toggleTheme(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Large Desktop Carousel
                    Expanded(
                      child: _buildDesktopCarousel(),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // RIGHT PANEL (~57%): surface color background, centered login form
          Expanded(
            flex: kAuthRightPanelFlex,
            child: Container(
              color: AppColors.surfaceOf(context),
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 36,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                          maxWidth: kAuthDesktopFormMaxWidth),
                      child: UnifiedAuthLoginForm(
                        mobileController: _readOnlyMobileController,
                        accentColor: _accent,
                        onTapMobileField: _openMobileScreen,
                        onContinue: _openMobileScreen,
                        onTroubleSigningIn: _openTroubleSigningInHelp,
                        isDesktop: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;

    if (screenWidth >= 900) {
      return _buildDesktopLayout(context);
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF071B2F), // Deep brand Navy
              Color(0xFF0A2D48),
              Color(0xFF0C5662),
              Color(0xFF0D9488), // DoctorNect Teal
            ],
            stops: [0.0, 0.35, 0.70, 1.0],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _buildTopBar(context),
              Expanded(child: _buildCarousel()),
              _buildBottomActionSheet(context),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reusable login form for Screen 1 (shared across mobile bottom sheet and desktop panel).
class UnifiedAuthLoginForm extends StatelessWidget {
  const UnifiedAuthLoginForm({
    super.key,
    required this.mobileController,
    required this.accentColor,
    required this.onTapMobileField,
    required this.onContinue,
    required this.onTroubleSigningIn,
    this.isDesktop = false,
  });

  final TextEditingController mobileController;
  final Color accentColor;
  final VoidCallback onTapMobileField;
  final VoidCallback onContinue;
  final VoidCallback onTroubleSigningIn;
  final bool isDesktop;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "Let's get started! Enter your mobile number",
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: isDesktop ? 22 : 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimaryOf(context),
            letterSpacing: isDesktop ? -0.4 : -0.2,
            height: 1.25,
          ),
        ),
        if (isDesktop) ...[
          const SizedBox(height: 8),
          Text(
            'Login or sign up to book appointments, consult doctors & order medicines',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondaryOf(context),
              height: 1.4,
            ),
          ),
        ],
        SizedBox(height: isDesktop ? 22 : 14),
        UnifiedAuthMobileField(
          controller: mobileController,
          readOnly: true,
          borderRadius: 12,
          fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          borderColor: AppColors.borderOf(context),
          onTap: onTapMobileField,
        ),
        SizedBox(height: isDesktop ? 16 : 12),
        SizedBox(
          height: isDesktop ? 50 : 48,
          child: FilledButton(
            onPressed: onContinue,
            style: FilledButton.styleFrom(
              backgroundColor: accentColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Continue',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ),
        SizedBox(height: isDesktop ? 14 : 10),
        Center(
          child: TextButton(
            onPressed: onTroubleSigningIn,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              'Trouble signing in?',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? const Color(0xFF38BDF8) : AppColors.patientTeal,
              ),
            ),
          ),
        ),
        if (isDesktop) ...[
          const SizedBox(height: 24),
          Text(
            'By continuing, you agree to our Terms & Conditions',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              color: AppColors.textSecondaryOf(context),
            ),
          ),
        ],
      ],
    );
  }
}

/// Simple help bottom sheet for Screen 1 ("Trouble signing in?").
class _WelcomeHelpBottomSheet extends StatelessWidget {
  const _WelcomeHelpBottomSheet({required this.onOpenSupport});

  final VoidCallback onOpenSupport;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderOf(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Icon(
                Icons.help_outline_rounded,
                color: AppColors.patientTeal,
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Trouble signing in?',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildHelpTile(
            context,
            icon: Icons.sms_failed_outlined,
            title: "Didn't receive the OTP?",
            description:
                'Verify your cellular network coverage and check SMS filters. You can resend the OTP after 30 seconds.',
          ),
          const SizedBox(height: 12),
          _buildHelpTile(
            context,
            icon: Icons.phone_android_outlined,
            title: 'Changed your mobile number?',
            description:
                'DoctorNect links your permanent account to your phone number. Reach out to our support team to update your profile.',
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onOpenSupport,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.patientTeal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.support_agent_rounded, size: 20),
            label: const Text(
              'Contact Support',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    final isDark = AppColors.isDark(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppColors.patientTeal),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12,
                    height: 1.35,
                    color: AppColors.textSecondaryOf(context),
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
