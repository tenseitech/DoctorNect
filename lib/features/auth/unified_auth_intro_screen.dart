import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/auth/unified_auth_flow_controller.dart';
import '../../core/enums/user_type.dart';
import '../../core/layout/responsive_layout.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme_controller.dart';
import '../../core/theme/app_typography.dart';
import '../../core/validators/form_validators.dart';
import '../../widgets/otp_input.dart';
import 'trouble_signing_in_screen.dart';
import 'unified_auth_expand_route.dart';
import 'unified_mobile_auth_screen.dart';
import 'widgets/unified_auth_mobile_field.dart';

/// Intro screen shown after role selection, before the full mobile-number entry screen.
class UnifiedAuthIntroScreen extends StatefulWidget {
  const UnifiedAuthIntroScreen({
    super.key,
    required this.role,
    this.accentColor,
  });

  final UserType role;
  final Color? accentColor;

  @override
  State<UnifiedAuthIntroScreen> createState() => _UnifiedAuthIntroScreenState();
}

class _IntroSlideContent {
  const _IntroSlideContent({
    required this.headline,
    this.supportingText,
    this.illustrationAsset,
    this.placeholderIcon,
  });

  final String headline;
  final String? supportingText;
  final String? illustrationAsset;
  final IconData? placeholderIcon;
}

const _kIntroIllustrationAsset = 'assets/images/doctor_illustration.jpg';

abstract final class _IntroTheme {
  static const sheetRadius = 28.0;
  static const inputRadius = 12.0;
  static const desktopInputRadius = 14.0;
  static const desktopCardRadius = 22.0;
  static const desktopRightBg = Color(0xFFF7F9FC);
  static const desktopRightBgTint = Color(0xFFEEF3FB);

  /// Brand accent layered over decorative graphics.
  static const meshSky = Color(0xFF38BDF8);

  /// Narrow-layout horizontal inset — matches the white auth sheet.
  static const mobileHorizontalPadding = 22.0;
}

typedef _DesktopFeatureItem = ({IconData icon, String label});

class _UnifiedAuthIntroScreenState extends State<UnifiedAuthIntroScreen> {
  final _mobileController = TextEditingController();
  final _focusNode = FocusNode();
  final _pageController = PageController();

  /// Only driven by the desktop card, which runs the flow inline. The narrow
  /// layout hands off to [UnifiedMobileAuthScreen], which owns its own.
  late final UnifiedAuthFlowController _desktopFlow;

  bool _transitioning = false;
  int _currentSlide = 0;
  Timer? _desktopCarouselTimer;
  bool _desktopCarouselAutoPlay = false;

  static const _desktopCarouselInterval = Duration(seconds: 5);
  static const _desktopCarouselAnimDuration = Duration(milliseconds: 450);

  bool get _isDoctor => widget.role == UserType.doctor;

  Color get _accent => widget.accentColor ?? _defaultAccent;

  Color get _defaultAccent => switch (widget.role) {
        UserType.doctor => AppColors.doctorBlue,
        UserType.patient => AppColors.patientTeal,
        UserType.medicalStore => AppColors.pharmacyGreen,
        UserType.lab => AppColors.labPurple,
        UserType.ambulance => const Color(0xFFDC2626),
        _ => AppColors.doctorBlue,
      };

  IconData get _roleIcon => switch (widget.role) {
        UserType.doctor => Icons.medical_services_outlined,
        UserType.patient => Icons.person_outline,
        UserType.medicalStore => Icons.local_pharmacy_outlined,
        UserType.lab => Icons.biotech_outlined,
        UserType.ambulance => Icons.emergency_outlined,
        _ => Icons.local_hospital_outlined,
      };

  List<_IntroSlideContent> get _slides => switch (widget.role) {
        UserType.doctor => const [
            _IntroSlideContent(
              headline: 'Manage patients with ease',
              supportingText:
                  'Appointments, prescriptions and clinical notes — all in one secure workspace built for doctors.',
              illustrationAsset: _kIntroIllustrationAsset,
            ),
            _IntroSlideContent(
              headline: 'Write prescriptions digitally',
              supportingText:
                  'Create, share and track prescriptions with patients and pharmacies in a few taps.',
              placeholderIcon: Icons.medication_outlined,
            ),
            _IntroSlideContent(
              headline: 'Your clinic, organized',
              supportingText:
                  'Stay on top of schedules, follow-ups and patient records without the paperwork.',
              placeholderIcon: Icons.calendar_month_outlined,
            ),
          ],
        UserType.patient => const [
            _IntroSlideContent(
              headline: 'Your health, in your hands',
              supportingText:
                  'Book doctors, track prescriptions, and manage lab reports from one secure app.',
              illustrationAsset: _kIntroIllustrationAsset,
            ),
            _IntroSlideContent(
              headline: 'Book appointments easily',
              supportingText:
                  'Find trusted doctors near you and schedule visits in minutes.',
              illustrationAsset: _kIntroIllustrationAsset,
            ),
            _IntroSlideContent(
              headline: 'Care when you need it',
              supportingText:
                  'Access prescriptions, reports, and emergency services anytime.',
              illustrationAsset: _kIntroIllustrationAsset,
            ),
            _IntroSlideContent(
              headline: 'Book lab tests and ambulance when you need them',
              illustrationAsset: _kIntroIllustrationAsset,
            ),
          ],
        UserType.medicalStore => const [
            _IntroSlideContent(
              headline: 'Streamline your pharmacy',
              supportingText:
                  'Receive digital prescriptions and serve patients faster from one workspace.',
              illustrationAsset: _kIntroIllustrationAsset,
            ),
            _IntroSlideContent(
              headline: 'Manage orders digitally',
              supportingText:
                  'Track dispensing, inventory, and patient requests without the paperwork.',
              illustrationAsset: _kIntroIllustrationAsset,
            ),
            _IntroSlideContent(
              headline: 'Connect with care partners',
              supportingText:
                  'Work seamlessly with doctors and patients on DoctorNect.',
              illustrationAsset: _kIntroIllustrationAsset,
            ),
            _IntroSlideContent(
              headline: 'Grow your pharmacy with DoctorNect',
              illustrationAsset: _kIntroIllustrationAsset,
            ),
          ],
        UserType.lab => const [
            _IntroSlideContent(
              headline: 'Simplify lab operations',
              supportingText:
                  'Manage test orders, samples, and results from one connected dashboard.',
              illustrationAsset: _kIntroIllustrationAsset,
            ),
            _IntroSlideContent(
              headline: 'Digital test reports',
              supportingText:
                  'Upload results and notify patients instantly — no manual follow-ups.',
              illustrationAsset: _kIntroIllustrationAsset,
            ),
            _IntroSlideContent(
              headline: 'Manage sample requests',
              supportingText:
                  'Track walk-ins, home collections, and doctor orders in real time.',
              illustrationAsset: _kIntroIllustrationAsset,
            ),
            _IntroSlideContent(
              headline: 'Partner with doctors on DoctorNect',
              illustrationAsset: _kIntroIllustrationAsset,
            ),
          ],
        UserType.ambulance => const [
            _IntroSlideContent(
              headline: 'Respond faster, save lives',
              supportingText:
                  'Accept emergency bookings and reach patients quickly when every minute counts.',
              illustrationAsset: _kIntroIllustrationAsset,
            ),
            _IntroSlideContent(
              headline: 'Real-time dispatch alerts',
              supportingText:
                  'Navigate, accept requests, and stay coordinated on every call.',
              illustrationAsset: _kIntroIllustrationAsset,
            ),
            _IntroSlideContent(
              headline: 'Quick patient handoff',
              supportingText:
                  'Share trip details and coordinate smoothly with hospitals and care teams.',
              illustrationAsset: _kIntroIllustrationAsset,
            ),
            _IntroSlideContent(
              headline: 'Keep your fleet available and responsive',
              illustrationAsset: _kIntroIllustrationAsset,
            ),
          ],
        _ => const [
            _IntroSlideContent(
              headline: 'Your health journey starts here with DoctorNect',
              illustrationAsset: _kIntroIllustrationAsset,
            ),
            _IntroSlideContent(
              headline: 'One platform for every healthcare role',
              illustrationAsset: _kIntroIllustrationAsset,
            ),
            _IntroSlideContent(
              headline: 'Secure, simple and built for mobile',
              illustrationAsset: _kIntroIllustrationAsset,
            ),
            _IntroSlideContent(
              headline: 'Join thousands on DoctorNect today',
              illustrationAsset: _kIntroIllustrationAsset,
            ),
          ],
      };

  /// Role-specific value props on the desktop brand panel (same styling for all).
  List<_DesktopFeatureItem> get _desktopFeatureBullets => switch (widget.role) {
        UserType.doctor => const [
            (
              icon: Icons.lock_outline_rounded,
              label: 'Secure patient records',
            ),
            (
              icon: Icons.receipt_long_outlined,
              label: 'Digital prescriptions',
            ),
            (icon: Icons.bolt_outlined, label: 'Instant consultations'),
          ],
        UserType.patient => const [
            (
              icon: Icons.event_available_outlined,
              label: 'Book appointments easily'
            ),
            (
              icon: Icons.medication_outlined,
              label: 'Access prescriptions anytime',
            ),
            (
              icon: Icons.video_call_outlined,
              label: 'Video consult top doctors',
            ),
          ],
        UserType.medicalStore => const [
            (
              icon: Icons.inventory_2_outlined,
              label: 'Manage orders digitally',
            ),
            (
              icon: Icons.receipt_long_outlined,
              label: 'Track prescriptions',
            ),
            (
              icon: Icons.hub_outlined,
              label: 'Connect with patients & doctors',
            ),
          ],
        UserType.lab => const [
            (
              icon: Icons.description_outlined,
              label: 'Digital test reports',
            ),
            (
              icon: Icons.biotech_outlined,
              label: 'Manage sample requests',
            ),
            (
              icon: Icons.speed_outlined,
              label: 'Faster patient turnaround',
            ),
          ],
        UserType.ambulance => const [
            (
              icon: Icons.notifications_active_outlined,
              label: 'Real-time dispatch alerts',
            ),
            (
              icon: Icons.transfer_within_a_station_outlined,
              label: 'Quick patient handoff',
            ),
            (
              icon: Icons.local_hospital_outlined,
              label: 'Coordinate with hospitals',
            ),
          ],
        _ => const [
            (icon: Icons.lock_outline_rounded, label: 'Secure patient records'),
            (
              icon: Icons.receipt_long_outlined,
              label: 'Digital prescriptions',
            ),
            (icon: Icons.bolt_outlined, label: 'Instant consultations'),
          ],
      };

  List<Color> get _gradientColors {
    final base = _accent;
    return switch (widget.role) {
      UserType.doctor => [
          const Color(0xFF0A2F6B),
          const Color(0xFF123E8A),
          base,
        ],
      UserType.patient => [
          const Color(0xFF064E3B),
          const Color(0xFF0B6B58),
          base,
        ],
      UserType.medicalStore => [
          const Color(0xFF065F46),
          const Color(0xFF047857),
          base,
        ],
      UserType.lab => [
          const Color(0xFF312E81),
          const Color(0xFF4338CA),
          base,
        ],
      UserType.ambulance => [
          const Color(0xFF7F1D1D),
          const Color(0xFFB91C1C),
          base,
        ],
      _ => [
          base.withValues(alpha: 0.95),
          base,
        ],
    };
  }

  /// Desktop left-panel gradient — same direction as the doctor variant, recolored
  /// per role using the welcome screen's accent palette.
  List<Color> get _desktopBrandGradient {
    final stops = _gradientColors;
    if (stops.length < 3) return stops;
    return [
      Color.lerp(stops.first, Colors.black, 0.12) ?? stops.first,
      stops[0],
      stops[1],
      stops[2],
    ];
  }

  /// Narrow-layout hero wash. Extends the role gradient with a deepened top and
  /// a lifted tail so the section reads with depth instead of as a flat fill.
  List<Color> get _mobileHeroGradient {
    final base = _gradientColors;
    return [
      Color.lerp(base.first, Colors.black, 0.22) ?? base.first,
      ...base,
      Color.lerp(base.last, Colors.white, 0.08) ?? base.last,
    ];
  }

  @override
  void initState() {
    super.initState();
    _desktopFlow = UnifiedAuthFlowController(role: widget.role);
    _pageController.addListener(_onPageScroll);
  }

  @override
  void dispose() {
    _stopDesktopCarouselTimer();
    _pageController.removeListener(_onPageScroll);
    _pageController.dispose();
    _mobileController.dispose();
    _focusNode.dispose();
    _desktopFlow.dispose();
    super.dispose();
  }

  void _syncDesktopCarouselAutoPlay(bool enabled) {
    if (_desktopCarouselAutoPlay == enabled) return;
    _desktopCarouselAutoPlay = enabled;
    if (enabled) {
      _startDesktopCarouselTimer();
    } else {
      _stopDesktopCarouselTimer();
    }
  }

  void _startDesktopCarouselTimer() {
    _desktopCarouselTimer?.cancel();
    _desktopCarouselTimer = Timer.periodic(_desktopCarouselInterval, (_) {
      if (!mounted || !_desktopCarouselAutoPlay) return;
      _advanceDesktopCarousel();
    });
  }

  void _stopDesktopCarouselTimer() {
    _desktopCarouselTimer?.cancel();
    _desktopCarouselTimer = null;
  }

  void _restartDesktopCarouselTimer() {
    if (!_desktopCarouselAutoPlay) return;
    _startDesktopCarouselTimer();
  }

  void _advanceDesktopCarousel() {
    if (!mounted || _slides.isEmpty) return;
    final next = (_currentSlide + 1) % _slides.length;
    _pageController.animateToPage(
      next,
      duration: _desktopCarouselAnimDuration,
      curve: Curves.easeInOut,
    );
  }

  void _onPageScroll() {
    final page = _pageController.page?.round() ?? 0;
    if (page != _currentSlide && mounted) {
      setState(() => _currentSlide = page);
    }
  }

  /// Narrow layout only: the compact field expands into the full-screen
  /// mobile-number step via Hero. The desktop card runs the flow inline and
  /// never calls this.
  Future<void> _openFullMobileScreen() async {
    if (_transitioning || !mounted) return;
    _transitioning = true;
    _focusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();

    await Navigator.of(context).push<void>(
      UnifiedAuthExpandRoute<void>(
        screen: UnifiedMobileAuthScreen(
          role: widget.role,
          accentColor: _accent,
          initialMobile: _mobileController.text,
          mobileHeroTag: UnifiedAuthMobileHero.tagFor(widget.role),
          focusMobileAfterTransition: true,
        ),
      ),
    );

    if (mounted) _transitioning = false;
  }

  void _onFieldEngaged() {
    _openFullMobileScreen();
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _openTroubleSigningInHelp() {
    _dismissKeyboard();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TroubleSigningInScreen(
          accentColor: _accent,
          onReenterMobile: () {
            // No-op on the narrow layout, which never advances this flow.
            if (_desktopFlow.step == UnifiedAuthStep.otp) {
              _desktopFlow.backToMobile();
            }
            _focusNode.requestFocus();
          },
        ),
      ),
    );
  }

  void _goToSlide(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
    _restartDesktopCarouselTimer();
  }

  void _previousSlide() {
    if (_currentSlide <= 0) {
      _goToSlide(_slides.length - 1);
      return;
    }
    _goToSlide(_currentSlide - 1);
  }

  Widget _buildSlideContent({
    required _IntroSlideContent slide,
    required double illustrationHeight,
    required bool compactHeight,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compactHeight ? 22 : 28),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: _IntroIllustration(
                assetPath: slide.illustrationAsset,
                placeholderIcon: slide.placeholderIcon ?? _roleIcon,
                height: illustrationHeight,
                fallbackIcon: _roleIcon,
                onDarkBackground: true,
              ),
            ),
          ),
          SizedBox(height: compactHeight ? 10 : 16),
          Text(
            slide.headline,
            maxLines: compactHeight ? 2 : 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: compactHeight
                  ? AppTypography.headlineSmall
                  : AppTypography.headlineMedium,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.35,
              letterSpacing: -0.2,
            ),
          ),
          if (slide.supportingText != null) ...[
            SizedBox(height: compactHeight ? 8 : 10),
            Text(
              slide.supportingText!,
              maxLines: compactHeight ? 2 : 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: AppTypography.bodySmall,
                fontWeight: FontWeight.w400,
                color: Colors.white.withValues(alpha: 0.82),
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDesktopIntroLayout(BuildContext context) {
    final isDark = AppColors.isDark(context);
    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : _IntroTheme.desktopRightBg,
      body: GestureDetector(
        onTap: _dismissKeyboard,
        behavior: HitTestBehavior.opaque,
        child: Row(
          children: [
            Expanded(child: _buildDesktopBrandPanel(context)),
            Expanded(child: _buildDesktopAuthPanel(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopBrandPanel(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _desktopBrandGradient,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _DesktopBrandBackdrop(accent: _accent),
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Scale with the panel so narrow desktops don't get a graphic
                // that crowds the feature list.
                final graphicSize =
                    (constraints.maxWidth * 0.56).clamp(230.0, 430.0);

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      right: -graphicSize * 0.16,
                      bottom: -graphicSize * 0.14,
                      child: _BrandGraphic(size: graphicSize),
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
                final heroHeight =
                    (constraints.maxHeight * 0.26).clamp(150.0, 220.0);

                final panel = Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 56,
                    vertical: tall ? 48 : 32,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _FadeSlideIn(
                        delay: Duration.zero,
                        child: Row(
                          children: [
                            _DesktopBackButton(
                              onPressed: () => Navigator.of(context).maybePop(),
                            ),
                            const SizedBox(width: 18),
                            _DesktopBrandMark(
                              accent: _accent,
                              icon: _roleIcon,
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _FadeSlideIn(
                            delay: const Duration(milliseconds: 90),
                            child: SizedBox(
                              height: heroHeight,
                              child: PageView.builder(
                                controller: _pageController,
                                itemCount: _slides.length,
                                onPageChanged: (index) {
                                  setState(() => _currentSlide = index);
                                  _restartDesktopCarouselTimer();
                                },
                                itemBuilder: (context, index) {
                                  return Align(
                                    alignment: Alignment.centerLeft,
                                    child: _DesktopHeroText(
                                      slide: _slides[index],
                                      headlineSize: tall ? 44 : 38,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          _FadeSlideIn(
                            delay: const Duration(milliseconds: 160),
                            child: _CarouselDots(
                              count: _slides.length,
                              currentIndex: _currentSlide,
                              onDotTap: _goToSlide,
                            ),
                          ),
                          SizedBox(height: tall ? 44 : 32),
                          _FadeSlideIn(
                            delay: const Duration(milliseconds: 230),
                            child: _DesktopFeatureBullets(
                              features: _desktopFeatureBullets,
                              accent: _accent,
                            ),
                          ),
                        ],
                      ),
                      _FadeSlideIn(
                        delay: const Duration(milliseconds: 320),
                        child: _DesktopTrustLine(accent: _accent),
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

  Widget _buildDesktopAuthPanel(BuildContext context) {
    final isDark = AppColors.isDark(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? const [AppColors.darkBackground, AppColors.darkSurface]
              : const [
                  _IntroTheme.desktopRightBg,
                  _IntroTheme.desktopRightBgTint,
                ],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _DesktopAuthBackdrop(accent: _accent),
          SafeArea(
            child: Stack(
              children: [
                Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 48, vertical: 56),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: _FadeSlideIn(
                        delay: const Duration(milliseconds: 120),
                        child: _DesktopAuthCard(
                          accent: _accent,
                          flow: _desktopFlow,
                          mobileController: _mobileController,
                          focusNode: _focusNode,
                          onTroubleSigningIn: _openTroubleSigningInHelp,
                        ),
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  top: 20,
                  right: 28,
                  child: _DesktopIntroThemeToggle(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileIntroLayout(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    final heroTag = UnifiedAuthMobileHero.tagFor(widget.role);
    final screenHeight = constraints.hasBoundedHeight
        ? constraints.maxHeight
        : MediaQuery.sizeOf(context).height;
    final screenWidth = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : MediaQuery.sizeOf(context).width;
    final compactHeight = screenHeight < 680;
    final illustrationHeight =
        (screenHeight * (compactHeight ? 0.24 : 0.28)).clamp(140.0, 260.0);
    // Sized off the viewport and pushed partly off-canvas so the line-art adds
    // depth in the corner without competing with the carousel.
    final graphicSize = (screenWidth * 0.58).clamp(165.0, 250.0);

    return Scaffold(
      backgroundColor: _gradientColors.first,
      // Tapping the field routes to the full mobile-auth screen, so no keyboard
      // is expected here; avoiding the inset keeps the hero section from
      // collapsing below its intrinsic height.
      resizeToAvoidBottomInset: false,
      body: GestureDetector(
        onTap: _dismissKeyboard,
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _mobileHeroGradient,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _MobileBrandBackdrop(
                        accent: _accent,
                        width: screenWidth,
                      ),
                    ),
                    if (_isDoctor)
                      Positioned(
                        right: -graphicSize * 0.36,
                        bottom: -graphicSize * 0.30,
                        child: Opacity(
                          opacity: AppColors.isDark(context) ? 0.72 : 1,
                          child: _BrandGraphic(size: graphicSize),
                        ),
                      ),
                    SafeArea(
                      bottom: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.arrow_back_rounded),
                                  onPressed: () =>
                                      Navigator.of(context).maybePop(),
                                  color: Colors.white,
                                  tooltip: 'Back',
                                ),
                                const Spacer(),
                                const _MobileIntroThemeToggle(),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              _IntroTheme.mobileHorizontalPadding,
                              0,
                              _IntroTheme.mobileHorizontalPadding,
                              0,
                            ),
                            child: const Align(
                              alignment: Alignment.centerLeft,
                              child: _MobileBrandWordmark(),
                            ),
                          ),
                          SizedBox(height: compactHeight ? 8 : 14),
                          Expanded(
                            child: PageView.builder(
                              controller: _pageController,
                              itemCount: _slides.length,
                              onPageChanged: (index) {
                                setState(() => _currentSlide = index);
                              },
                              itemBuilder: (context, index) {
                                return _buildSlideContent(
                                  slide: _slides[index],
                                  illustrationHeight: illustrationHeight,
                                  compactHeight: compactHeight,
                                );
                              },
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              _IntroTheme.mobileHorizontalPadding,
                              compactHeight ? 8 : 12,
                              _IntroTheme.mobileHorizontalPadding,
                              compactHeight ? 14 : 20,
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _IntroCarouselIndicator(
                                count: _slides.length,
                                currentIndex: _currentSlide,
                                onPrevious: _previousSlide,
                                onDotTap: _goToSlide,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surfaceOf(context),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(_IntroTheme.sheetRadius),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.isDark(context)
                        ? Colors.black.withValues(alpha: 0.42)
                        : const Color(0xFF0B1841).withValues(alpha: 0.20),
                    blurRadius: 36,
                    offset: const Offset(0, -14),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: AppColors.isDark(context) ? 0.18 : 0.06,
                    ),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(_IntroTheme.sheetRadius),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
                    child: _IntroAuthForm(
                      heroTag: heroTag,
                      accent: _accent,
                      mobileController: _mobileController,
                      focusNode: _focusNode,
                      onFieldEngaged: _onFieldEngaged,
                      onTroubleSigningIn: _openTroubleSigningInHelp,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final splitLayout =
            constraints.maxWidth >= ResponsiveLayout.mediumMaxWidth;
        _syncDesktopCarouselAutoPlay(splitLayout);

        return splitLayout
            ? _buildDesktopIntroLayout(context)
            : _buildMobileIntroLayout(context, constraints);
      },
    );
  }
}

// ─── Intro layout widgets ───────────────────────────────────────────────────

/// Text wordmark for the narrow layout.
class _MobileBrandWordmark extends StatelessWidget {
  const _MobileBrandWordmark();

  @override
  Widget build(BuildContext context) {
    return Text(
      'DoctorNect',
      style: GoogleFonts.inter(
        fontSize: AppTypography.displayMedium,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        height: 1.1,
        color: Colors.white,
      ),
    );
  }
}

/// Icon-only theme toggle for the narrow intro hero bar.
class _MobileIntroThemeToggle extends StatelessWidget {
  const _MobileIntroThemeToggle();

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
                  transitionBuilder: (child, anim) => ScaleTransition(
                    scale: anim,
                    child: child,
                  ),
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

/// Narrow-layout counterpart to [_DesktopBrandBackdrop]: off-canvas colour
/// blobs and a faint dot lattice layered over the base gradient.
class _MobileBrandBackdrop extends StatelessWidget {
  const _MobileBrandBackdrop({required this.accent, required this.width});

  final Color accent;
  final double width;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final highlight = Color.lerp(accent, Colors.white, 0.38) ?? accent;
    final lift = Color.lerp(accent, Colors.white, 0.14) ?? accent;

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -width * 0.44,
            left: -width * 0.34,
            child: _SoftGlow(
              diameter: width * 1.15,
              color: highlight.withValues(alpha: isDark ? 0.18 : 0.26),
            ),
          ),
          Positioned(
            top: -width * 0.20,
            right: -width * 0.28,
            child: _SoftGlow(
              diameter: width * 0.88,
              color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.12),
            ),
          ),
          Positioned(
            bottom: -width * 0.30,
            left: -width * 0.26,
            child: _SoftGlow(
              diameter: width * 0.95,
              color: lift.withValues(alpha: isDark ? 0.14 : 0.22),
            ),
          ),
          Opacity(
            opacity: isDark ? 0.34 : 0.5,
            child: const CustomPaint(painter: _DotLatticePainter()),
          ),
          // Deepens the edge meeting the sheet so its shadow keeps definition.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  const Color(0xFF061131)
                      .withValues(alpha: isDark ? 0.38 : 0.26),
                ],
                stops: const [0.6, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroAuthForm extends StatefulWidget {
  const _IntroAuthForm({
    required this.heroTag,
    required this.accent,
    required this.mobileController,
    required this.focusNode,
    required this.onFieldEngaged,
    required this.onTroubleSigningIn,
  });

  final String heroTag;
  final Color accent;
  final TextEditingController mobileController;
  final FocusNode focusNode;
  final VoidCallback onFieldEngaged;
  final VoidCallback onTroubleSigningIn;

  @override
  State<_IntroAuthForm> createState() => _IntroAuthFormState();
}

class _IntroAuthFormState extends State<_IntroAuthForm> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (!mounted) return;
    final focused = widget.focusNode.hasFocus;
    if (focused != _focused) setState(() => _focused = focused);
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = AppColors.borderOf(context);
    final fieldFill = AppColors.cardBgOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(
              color: borderColor,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
        Text(
          'Let\'s get started! Enter your mobile number',
          style: GoogleFonts.inter(
            fontSize: AppTypography.titleMedium,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimaryOf(context),
            height: 1.35,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 20),
        Hero(
          tag: widget.heroTag,
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder<Color?>(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              tween: ColorTween(
                end: _focused ? widget.accent : borderColor,
              ),
              builder: (context, animatedBorder, _) {
                return UnifiedAuthMobileField(
                  controller: widget.mobileController,
                  focusNode: widget.focusNode,
                  onTap: widget.onFieldEngaged,
                  onChanged: (_) => widget.onFieldEngaged(),
                  borderRadius: _IntroTheme.inputRadius,
                  fillColor: fieldFill,
                  borderColor: animatedBorder ?? borderColor,
                  boxShadow: [
                    BoxShadow(
                      color: widget.accent
                          .withValues(alpha: _focused ? 0.14 : 0.0),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: widget.onTroubleSigningIn,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: widget.accent,
            ),
            child: Text(
              'Trouble signing in?',
              style: GoogleFonts.inter(
                fontSize: AppTypography.bodySmall,
                fontWeight: FontWeight.w500,
                color: widget.accent,
                decoration: TextDecoration.underline,
                decorationColor: widget.accent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Reusable blurred circular "blob" used to build the mesh-gradient depth.
class _SoftGlow extends StatelessWidget {
  const _SoftGlow({required this.diameter, required this.color});

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

/// Off-canvas colour blobs plus a faint dot lattice, layered over the base
/// gradient so the panel reads as depth instead of a flat fill.
class _DesktopBrandBackdrop extends StatelessWidget {
  const _DesktopBrandBackdrop({required this.accent});

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
            child: _SoftGlow(
              diameter: 620,
              color: accent.withValues(alpha: 0.55),
            ),
          ),
          Positioned(
            top: -140,
            right: -190,
            child: _SoftGlow(
              diameter: 520,
              color: highlight.withValues(alpha: 0.28),
            ),
          ),
          Positioned(
            bottom: -260,
            left: -140,
            child: _SoftGlow(
              diameter: 600,
              color: lift.withValues(alpha: 0.30),
            ),
          ),
          Positioned(
            bottom: -200,
            right: -120,
            child: _SoftGlow(
              diameter: 460,
              color: accent.withValues(alpha: 0.34),
            ),
          ),
          const Opacity(
            opacity: 0.55,
            child: CustomPaint(painter: _DotLatticePainter()),
          ),
          // Deepens the lower edge so the trust badge keeps its contrast.
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

/// Soft decorative layer behind the desktop auth card — toned down for the
/// light right panel so the white card stays the focal point.
class _DesktopAuthBackdrop extends StatelessWidget {
  const _DesktopAuthBackdrop({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          final graphicSize = (w * 0.42).clamp(180.0, 320.0);

          return Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: -w * 0.22,
                top: -h * 0.12,
                child: _SoftGlow(
                  diameter: w * 0.72,
                  color: accent.withValues(alpha: isDark ? 0.14 : 0.10),
                ),
              ),
              Positioned(
                right: -w * 0.18,
                top: h * 0.08,
                child: _SoftGlow(
                  diameter: w * 0.55,
                  color: accent.withValues(alpha: isDark ? 0.12 : 0.08),
                ),
              ),
              Positioned(
                left: w * 0.08,
                bottom: -h * 0.14,
                child: _SoftGlow(
                  diameter: w * 0.62,
                  color: accent.withValues(alpha: isDark ? 0.10 : 0.07),
                ),
              ),
              Positioned(
                right: -w * 0.10,
                bottom: -h * 0.18,
                child: _SoftGlow(
                  diameter: w * 0.48,
                  color: accent.withValues(alpha: isDark ? 0.09 : 0.06),
                ),
              ),
              CustomPaint(
                painter: _DotLatticePainter(
                  dotColor: accent.withValues(alpha: isDark ? 0.08 : 0.055),
                ),
              ),
              Positioned(
                right: -graphicSize * 0.22,
                bottom: -graphicSize * 0.18,
                child: Opacity(
                  opacity: isDark ? 0.10 : 0.14,
                  child: _BrandGraphic(size: graphicSize),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DotLatticePainter extends CustomPainter {
  const _DotLatticePainter({this.dotColor});

  final Color? dotColor;

  static const _spacing = 26.0;
  static const _radius = 1.1;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = dotColor ?? Colors.white.withValues(alpha: 0.07);

    for (var y = _spacing; y < size.height; y += _spacing) {
      for (var x = _spacing; x < size.width; x += _spacing) {
        canvas.drawCircle(Offset(x, y), _radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotLatticePainter oldDelegate) =>
      dotColor != oldDelegate.dotColor;
}

/// Abstract stethoscope + heartbeat composition anchored to a lower corner of
/// the brand area, on both layouts. Purely decorative and kept low-contrast so
/// the headline stays dominant; callers scale it to the space available.
class _BrandGraphic extends StatelessWidget {
  const _BrandGraphic({required this.size});

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
            _SoftGlow(
              diameter: size * 0.95,
              color: _IntroTheme.meshSky.withValues(alpha: 0.20),
            ),
            CustomPaint(
              size: Size.square(size),
              painter: const _BrandGraphicPainter(),
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

class _BrandGraphicPainter extends CustomPainter {
  const _BrandGraphicPainter();

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
    const segments = 44;
    const sweep = 6.2831853 / segments;
    for (var i = 0; i < segments; i += 2) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: size.width * 0.58),
        i * sweep,
        sweep,
        false,
        dashRing,
      );
    }

    // Heartbeat trace across the middle of the composition.
    final trace = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withValues(alpha: 0.26)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final y = center.dy;
    final path = Path()
      ..moveTo(w * 0.14, y)
      ..lineTo(w * 0.32, y)
      ..lineTo(w * 0.38, y - w * 0.09)
      ..lineTo(w * 0.45, y + w * 0.11)
      ..lineTo(w * 0.52, y - w * 0.17)
      ..lineTo(w * 0.59, y + w * 0.06)
      ..lineTo(w * 0.65, y)
      ..lineTo(w * 0.86, y);

    canvas.drawPath(path, trace);
  }

  @override
  bool shouldRepaint(_BrandGraphicPainter oldDelegate) => false;
}

/// One-shot fade + slide entrance used to stagger the brand panel content.
class _FadeSlideIn extends StatefulWidget {
  const _FadeSlideIn({
    required this.child,
    this.delay = Duration.zero,
  });

  final Widget child;
  final Duration delay;

  static const _slideDistance = 18.0;

  @override
  State<_FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<_FadeSlideIn>
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
            offset: Offset(0, (1 - _curve.value) * _FadeSlideIn._slideDistance),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Icon-only theme toggle for the desktop auth panel (matches narrow layout).
class _DesktopIntroThemeToggle extends StatelessWidget {
  const _DesktopIntroThemeToggle();

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

class _DesktopBackButton extends StatelessWidget {
  const _DesktopBackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: const SizedBox(
          width: 38,
          height: 38,
          child: Icon(Icons.arrow_back_rounded, size: 19, color: Colors.white),
        ),
      ),
    );
  }
}

class _DesktopBrandMark extends StatelessWidget {
  const _DesktopBrandMark({required this.accent, required this.icon});

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
          child: Icon(
            icon,
            size: 19,
            color: accent,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          'DoctorNect',
          style: GoogleFonts.inter(
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

class _DesktopHeroText extends StatelessWidget {
  const _DesktopHeroText({
    required this.slide,
    required this.headlineSize,
  });

  final _IntroSlideContent slide;
  final double headlineSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Text(
            slide.headline,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: headlineSize,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.1,
              letterSpacing: -1.4,
            ),
          ),
        ),
        if (slide.supportingText != null) ...[
          const SizedBox(height: 20),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(
              slide.supportingText!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: Colors.white.withValues(alpha: 0.74),
                height: 1.6,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Animated pill dots shared by both layouts.
class _CarouselDots extends StatelessWidget {
  const _CarouselDots({
    required this.count,
    required this.currentIndex,
    required this.onDotTap,
  });

  final int count;
  final int currentIndex;
  final ValueChanged<int> onDotTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(count, (index) {
        final active = index == currentIndex;
        return Padding(
          padding: EdgeInsets.only(right: index == count - 1 ? 0 : 7),
          child: GestureDetector(
            onTap: () => onDotTap(index),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              width: active ? 26 : 6,
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                color: active
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.26),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.45),
                          blurRadius: 10,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _DesktopFeatureBullets extends StatelessWidget {
  const _DesktopFeatureBullets({required this.features, required this.accent});

  final List<_DesktopFeatureItem> features;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final last = features.last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final feature in features)
          Padding(
            padding: EdgeInsets.only(bottom: feature == last ? 0 : 14),
            child: _DesktopFeatureBullet(
              icon: feature.icon,
              label: feature.label,
              accent: accent,
            ),
          ),
      ],
    );
  }
}

class _DesktopFeatureBullet extends StatefulWidget {
  const _DesktopFeatureBullet({
    required this.icon,
    required this.label,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final Color accent;

  @override
  State<_DesktopFeatureBullet> createState() => _DesktopFeatureBulletState();
}

class _DesktopFeatureBulletState extends State<_DesktopFeatureBullet> {
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
                    color:
                        Colors.white.withValues(alpha: _hovered ? 0.36 : 0.20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.accent
                          .withValues(alpha: _hovered ? 0.40 : 0.20),
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
                  style: GoogleFonts.inter(
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

class _DesktopTrustLine extends StatelessWidget {
  const _DesktopTrustLine({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _DesktopAvatarStack(accent: accent),
        const SizedBox(width: 14),
        Flexible(
          child: Text(
            'Trusted by 10,000+ doctors across India',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
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

class _DesktopAvatarStack extends StatelessWidget {
  const _DesktopAvatarStack({required this.accent});

  final Color accent;

  static const _size = 28.0;
  static const _overlap = 18.0;

  @override
  Widget build(BuildContext context) {
    final colors = [
      Color.lerp(accent, Colors.white, 0.35) ?? accent,
      accent,
      Color.lerp(accent, Colors.black, 0.18) ?? accent,
    ];

    return SizedBox(
      width: _overlap * (colors.length - 1) + _size,
      height: _size,
      child: Stack(
        children: List.generate(colors.length, (index) {
          return Positioned(
            left: index * _overlap,
            child: Container(
              width: _size,
              height: _size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors[index],
                border: Border.all(
                  color: accent,
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.person_rounded,
                size: 14,
                color: Colors.white.withValues(alpha: 0.92),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Pill CTA with desktop-appropriate hover lift and press compression.
class _DesktopPrimaryButton extends StatefulWidget {
  const _DesktopPrimaryButton({
    required this.label,
    required this.accent,
    required this.onPressed,
    this.enabled = true,
    this.loading = false,
    this.loadingLabel,
  });

  final String label;
  final Color accent;
  final VoidCallback onPressed;
  final bool enabled;
  final bool loading;
  final String? loadingLabel;

  @override
  State<_DesktopPrimaryButton> createState() => _DesktopPrimaryButtonState();
}

class _DesktopPrimaryButtonState extends State<_DesktopPrimaryButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.enabled && !widget.loading;
    final base = widget.accent;
    final lifted = Color.lerp(base, Colors.white, 0.10) ?? base;
    final hovered = _hovered && interactive;
    final pressed = _pressed && interactive;

    final fill = interactive
        ? (hovered
            ? [lifted, base]
            : [base, Color.lerp(base, Colors.black, 0.08) ?? base])
        : [
            Color.lerp(base, Colors.white, 0.62) ?? base,
            Color.lerp(base, Colors.white, 0.54) ?? base,
          ];

    return MouseRegion(
      cursor: interactive ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: interactive ? (_) => setState(() => _pressed = true) : null,
        onTapUp: interactive ? (_) => setState(() => _pressed = false) : null,
        onTapCancel:
            interactive ? () => setState(() => _pressed = false) : null,
        onTap: interactive ? widget.onPressed : null,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          scale: pressed ? 0.975 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            height: 54,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: fill,
              ),
              borderRadius: BorderRadius.circular(99),
              boxShadow: [
                BoxShadow(
                  color: base.withValues(
                    alpha: interactive ? (hovered ? 0.40 : 0.26) : 0.10,
                  ),
                  blurRadius: hovered ? 26 : 16,
                  offset: Offset(0, hovered ? 10 : 6),
                ),
              ],
            ),
            child: Center(
              child: widget.loading
                  ? _buildLoadingContent()
                  : _buildLabelContent(hovered),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingContent() {
    return _contentRow([
      const SizedBox(
        width: 19,
        height: 19,
        child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
      ),
      if (widget.loadingLabel != null) ...[
        const SizedBox(width: 11),
        _label(widget.loadingLabel!),
      ],
    ]);
  }

  Widget _buildLabelContent(bool hovered) {
    return _contentRow([
      _label(widget.label),
      const SizedBox(width: 8),
      AnimatedSlide(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        offset: Offset(hovered ? 0.22 : 0, 0),
        child: const Icon(
          Icons.arrow_forward_rounded,
          size: 18,
          color: Colors.white,
        ),
      ),
    ]);
  }

  /// Kept shrink-safe: the longest label ("Verify & continue") plus the arrow
  /// exceeds the card's inner width at the 900px breakpoint.
  Widget _contentRow(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _label(String text) {
    return Flexible(
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

/// The desktop card is a self-contained auth surface: it runs the whole
/// mobile → OTP flow inline through [UnifiedAuthFlowController] and never pushes
/// a route, unlike the narrow layout which expands into a full screen.
class _DesktopAuthCard extends StatefulWidget {
  const _DesktopAuthCard({
    required this.accent,
    required this.flow,
    required this.mobileController,
    required this.focusNode,
    required this.onTroubleSigningIn,
  });

  final Color accent;
  final UnifiedAuthFlowController flow;
  final TextEditingController mobileController;
  final FocusNode focusNode;
  final VoidCallback onTroubleSigningIn;

  @override
  State<_DesktopAuthCard> createState() => _DesktopAuthCardState();
}

class _DesktopAuthCardState extends State<_DesktopAuthCard> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
    widget.mobileController.addListener(_onDependencyChanged);
    widget.flow.addListener(_onDependencyChanged);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    widget.mobileController.removeListener(_onDependencyChanged);
    widget.flow.removeListener(_onDependencyChanged);
    super.dispose();
  }

  void _onFocusChange() {
    if (!mounted) return;
    final focused = widget.focusNode.hasFocus;
    if (focused != _focused) setState(() => _focused = focused);
  }

  void _onDependencyChanged() {
    if (mounted) setState(() {});
  }

  bool get _mobileValid {
    final digits =
        FormValidators.registrationMobileDigits(widget.mobileController.text);
    return digits != null && digits.length == 10;
  }

  void _submit() {
    final flow = widget.flow;
    if (flow.step == UnifiedAuthStep.mobile) {
      widget.focusNode.unfocus();
      flow.sendOtp(context, widget.mobileController.text);
    } else {
      flow.verifyOtp(context);
    }
  }

  void _changeNumber() {
    widget.flow.backToMobile();
    widget.focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final isMobileStep = widget.flow.step == UnifiedAuthStep.mobile;
    final isDark = AppColors.isDark(context);
    final cardColor = AppColors.surfaceOf(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(_IntroTheme.desktopCardRadius),
        border: Border.all(
          color: isDark
              ? AppColors.borderOf(context)
              : Colors.white.withValues(alpha: 0.85),
        ),
        boxShadow: [
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
            color: widget.accent.withValues(alpha: isDark ? 0.10 : 0.06),
            blurRadius: 60,
            spreadRadius: -12,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(38, 40, 38, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        widget.accent,
                        widget.accent.withValues(alpha: 0.78),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: widget.accent.withValues(alpha: 0.32),
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.medical_services_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 30,
                  height: 3,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        widget.accent.withValues(alpha: 0.55),
                        widget.accent.withValues(alpha: 0),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            AnimatedSize(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: isMobileStep
                    ? _buildMobileStep(context)
                    : _buildOtpStep(context),
              ),
            ),
            const SizedBox(height: 26),
            _DesktopPrimaryButton(
              label: isMobileStep ? 'Continue' : 'Verify & continue',
              loadingLabel: isMobileStep ? 'Sending OTP...' : 'Verifying...',
              accent: widget.accent,
              enabled: isMobileStep ? _mobileValid : widget.flow.otpValid,
              loading:
                  isMobileStep ? widget.flow.sendingOtp : widget.flow.verifying,
              onPressed: _submit,
            ),
            const SizedBox(height: 20),
            Center(
              child: TextButton(
                onPressed: widget.onTroubleSigningIn,
                style: TextButton.styleFrom(
                  foregroundColor: widget.accent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Trouble signing in?',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: widget.accent,
                    decoration: TextDecoration.underline,
                    decorationColor: widget.accent,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileStep(BuildContext context) {
    final borderBase = AppColors.borderOf(context);

    return Column(
      key: const ValueKey(UnifiedAuthStep.mobile),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Welcome to DoctorNect', style: _titleStyle(context)),
        const SizedBox(height: 10),
        Text(
          'Let\'s get started! Enter your mobile number',
          style: _subtitleStyle(context),
        ),
        const SizedBox(height: 30),
        Text('Mobile number', style: _fieldLabelStyle(context)),
        const SizedBox(height: 9),
        // No Hero and no tap handler here: this card is already the full form,
        // so the field just takes focus like any other web input.
        TweenAnimationBuilder<Color?>(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          tween: ColorTween(
            end: _focused ? widget.accent : borderBase,
          ),
          builder: (context, borderColor, _) {
            return UnifiedAuthMobileField(
              controller: widget.mobileController,
              focusNode: widget.focusNode,
              onSubmitted: (_) => _submit(),
              borderRadius: _IntroTheme.desktopInputRadius,
              fillColor: AppColors.cardBgOf(context),
              borderColor: borderColor ?? borderBase,
              boxShadow: [
                BoxShadow(
                  color: widget.accent.withValues(alpha: _focused ? 0.14 : 0.0),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildOtpStep(BuildContext context) {
    final flow = widget.flow;
    final countingDown = flow.otpCountdown > 0;

    return Column(
      key: const ValueKey(UnifiedAuthStep.otp),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Verify your number', style: _titleStyle(context)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                'Enter the 6-digit OTP sent to +91 ${flow.mobileDigits ?? ''}',
                style: _subtitleStyle(context),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: flow.busy ? null : _changeNumber,
              style: TextButton.styleFrom(
                foregroundColor: widget.accent,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Change',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: widget.accent,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        Text('One-time password', style: _fieldLabelStyle(context)),
        const SizedBox(height: 12),
        _buildOtpBoxes(flow),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: (flow.busy || countingDown)
                ? null
                : () => flow.resendOtp(context),
            style: TextButton.styleFrom(
              foregroundColor: widget.accent,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              countingDown
                  ? 'Resend OTP in ${flow.otpCountdown}s'
                  : 'Resend OTP',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: countingDown
                    ? AppColors.textSecondaryOf(context)
                    : widget.accent,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// [OtpInput]'s boxes are fixed-width and don't fit the card at the 900px
  /// breakpoint. `scaleDown` shrinks them only when the card is too narrow, so
  /// wider cards still render them at their natural size.
  Widget _buildOtpBoxes(UnifiedAuthFlowController flow) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: OtpInput.intrinsicRowWidth,
        child: OtpInput(
          accentColor: widget.accent,
          autofocus: true,
          onChanged: flow.setOtp,
          onCompleted: (_) => flow.verifyOtp(context),
        ),
      ),
    );
  }

  TextStyle _titleStyle(BuildContext context) => GoogleFonts.inter(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimaryOf(context),
        letterSpacing: -0.6,
        height: 1.2,
      );

  TextStyle _subtitleStyle(BuildContext context) => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: AppColors.textSecondaryOf(context),
        height: 1.5,
      );

  TextStyle _fieldLabelStyle(BuildContext context) => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimaryOf(context),
        height: 1.2,
      );
}

class _IntroIllustration extends StatelessWidget {
  const _IntroIllustration({
    required this.placeholderIcon,
    required this.height,
    required this.fallbackIcon,
    required this.onDarkBackground,
    this.assetPath,
  });

  final String? assetPath;
  final IconData placeholderIcon;
  final double height;
  final IconData fallbackIcon;
  final bool onDarkBackground;

  @override
  Widget build(BuildContext context) {
    final glowColor = onDarkBackground
        ? Colors.white.withValues(alpha: 0.16)
        : AppColors.doctorBlue.withValues(alpha: 0.08);

    // Never draw taller than the space the parent actually gave us, otherwise
    // the inner glow and image overflow on short screens.
    return LayoutBuilder(
      builder: (context, constraints) {
        var size = height;
        if (constraints.hasBoundedHeight) {
          size = size.clamp(0.0, constraints.maxHeight);
        }
        if (constraints.hasBoundedWidth) {
          size = size.clamp(0.0, constraints.maxWidth);
        }

        return SizedBox(
          height: size,
          width: double.infinity,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: size * 0.92,
                height: size * 0.92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [glowColor, glowColor.withValues(alpha: 0)],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: size * 0.04),
                child: assetPath != null
                    ? Image.asset(
                        assetPath!,
                        height: size,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => _PlaceholderIllustration(
                          icon: fallbackIcon,
                          height: size,
                          onDarkBackground: onDarkBackground,
                        ),
                      )
                    : _PlaceholderIllustration(
                        icon: placeholderIcon,
                        height: size,
                        onDarkBackground: onDarkBackground,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlaceholderIllustration extends StatelessWidget {
  const _PlaceholderIllustration({
    required this.icon,
    required this.height,
    required this.onDarkBackground,
  });

  final IconData icon;
  final double height;
  final bool onDarkBackground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: height * 0.62,
      height: height * 0.62,
      decoration: BoxDecoration(
        color: onDarkBackground
            ? Colors.white.withValues(alpha: 0.14)
            : AppColors.doctorBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: onDarkBackground
              ? Colors.white.withValues(alpha: 0.22)
              : AppColors.doctorBlue.withValues(alpha: 0.15),
        ),
      ),
      child: Icon(
        icon,
        size: height * 0.24,
        color: onDarkBackground
            ? Colors.white.withValues(alpha: 0.95)
            : AppColors.doctorBlue,
      ),
    );
  }
}

/// Uniform round dots for the narrow carousel — active dot is larger and brighter.
class _MobileCarouselDots extends StatelessWidget {
  const _MobileCarouselDots({
    required this.count,
    required this.currentIndex,
    required this.onDotTap,
  });

  final int count;
  final int currentIndex;
  final ValueChanged<int> onDotTap;

  static const _inactiveSize = 5.0;
  static const _activeSize = 9.0;
  static const _dotSpacing = 8.0;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(count, (index) {
        final active = index == currentIndex;
        return Padding(
          padding: EdgeInsets.only(right: index == count - 1 ? 0 : _dotSpacing),
          child: GestureDetector(
            onTap: () => onDotTap(index),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              width: active ? _activeSize : _inactiveSize,
              height: active ? _activeSize : _inactiveSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.28),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _IntroCarouselIndicator extends StatelessWidget {
  const _IntroCarouselIndicator({
    required this.count,
    required this.currentIndex,
    required this.onPrevious,
    required this.onDotTap,
  });

  final int count;
  final int currentIndex;
  final VoidCallback onPrevious;
  final ValueChanged<int> onDotTap;

  @override
  Widget build(BuildContext context) {
    final arrowColor = Colors.white.withValues(alpha: 0.72);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CarouselArrow(
          icon: Icons.chevron_left_rounded,
          onPressed: onPrevious,
          color: arrowColor,
        ),
        const SizedBox(width: 14),
        _MobileCarouselDots(
          count: count,
          currentIndex: currentIndex,
          onDotTap: onDotTap,
        ),
      ],
    );
  }
}

class _CarouselArrow extends StatelessWidget {
  const _CarouselArrow({
    required this.icon,
    required this.onPressed,
    required this.color,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }
}

/// Opens the intro screen for a role (used from role selection).
void openUnifiedAuthIntro(
  BuildContext context, {
  required UserType role,
  Color? accentColor,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => UnifiedAuthIntroScreen(
        role: role,
        accentColor: accentColor,
      ),
    ),
  );
}
