import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_controller.dart';
import '../../../core/utils/asset_resolver.dart';
import '../../../widgets/medibond_logo.dart';

/// Data model for healthcare carousel slides in AuthLayout.
class AuthLayoutSlideData {
  const AuthLayoutSlideData({
    required this.tagline,
    required this.imageAsset,
    this.fallbackIcon = Icons.medical_services_outlined,
  });

  final String tagline;
  final String imageAsset;
  final IconData fallbackIcon;
}

/// Default DoctorNect carousel slides shared across all auth flows.
const List<AuthLayoutSlideData> kDefaultAuthSlides = [
  AuthLayoutSlideData(
    tagline: 'Instant walk-in and clinic appointment booking',
    imageAsset: 'assets/images/intro_slide_1.webp',
    fallbackIcon: Icons.calendar_month_rounded,
  ),
  AuthLayoutSlideData(
    tagline: 'Find and consult trusted doctors near you',
    imageAsset: 'assets/images/intro_slide_2.webp',
    fallbackIcon: Icons.person_search_rounded,
  ),
  AuthLayoutSlideData(
    tagline: 'Diagnostic labs, pharmacy & ambulance in\u00A0one\u00A0app',
    imageAsset: 'assets/images/intro_slide_3.webp',
    fallbackIcon: Icons.local_hospital_rounded,
  ),
  AuthLayoutSlideData(
    tagline: 'Your complete digital health records, in one secure place',
    imageAsset: 'assets/images/intro_slide_4.webp',
    fallbackIcon: Icons.folder_shared_rounded,
  ),
];

/// Desktop split layout constants shared across all auth flows.
const int kAuthLeftPanelFlex = 43;
const int kAuthRightPanelFlex = 57;
const double kAuthLeftPanelMinWidth = 380.0;
const double kAuthDesktopFormMaxWidth = 480.0;

/// Reusable full-screen responsive layout for all authentication and onboarding screens.
///
/// Breakpoints:
/// - `width >= 900`: Full-screen split layout:
///   - LEFT (~43% flex): Brand navy/teal gradient, DoctorNect logo, theme toggle,
///     large healthcare carousel with bold taglines and dot indicators.
///   - RIGHT (~57% flex): Clean white/surface panel, full-height, centered form (maxWidth: ~480).
///     Back button and Help header at top of right panel.
/// - `width < 900`: Unaltered mobile layout (`mobileBody`).
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.mobileBody,
    required this.desktopForm,
    this.desktopLeftHero,
    this.onBack,
    this.showBackButton = false,
    this.onHelp,
    this.showHelpButton = false,
    this.formMaxWidth = kAuthDesktopFormMaxWidth,
    this.rightHeader,
    this.desktopBottomAction,
  });

  /// Widget rendered when screen width < 900px.
  final Widget mobileBody;

  /// Form content centered inside the desktop right panel.
  final Widget desktopForm;

  /// Optional custom left panel hero for desktop.
  /// If null, renders the standard DoctorNect 4-slide carousel.
  final Widget? desktopLeftHero;

  /// Desktop back action in right panel header.
  final VoidCallback? onBack;
  final bool showBackButton;

  /// Desktop help action in right panel header.
  final VoidCallback? onHelp;
  final bool showHelpButton;

  /// Max width constraint for desktop right panel form (default 440).
  final double formMaxWidth;

  /// Custom header widget for desktop right panel (replaces default back/help row).
  final Widget? rightHeader;

  /// Optional pinned bottom action for desktop right panel.
  final Widget? desktopBottomAction;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;

    if (screenWidth >= 900) {
      return _DesktopAuthScaffold(
        desktopForm: desktopForm,
        desktopLeftHero: desktopLeftHero,
        onBack: onBack,
        showBackButton: showBackButton,
        onHelp: onHelp,
        showHelpButton: showHelpButton,
        formMaxWidth: formMaxWidth,
        rightHeader: rightHeader,
        desktopBottomAction: desktopBottomAction,
      );
    }

    return mobileBody;
  }
}

class _DesktopAuthScaffold extends StatelessWidget {
  const _DesktopAuthScaffold({
    required this.desktopForm,
    this.desktopLeftHero,
    this.onBack,
    this.showBackButton = false,
    this.onHelp,
    this.showHelpButton = false,
    required this.formMaxWidth,
    this.rightHeader,
    this.desktopBottomAction,
  });

  final Widget desktopForm;
  final Widget? desktopLeftHero;
  final VoidCallback? onBack;
  final bool showBackButton;
  final VoidCallback? onHelp;
  final bool showHelpButton;
  final double formMaxWidth;
  final Widget? rightHeader;
  final Widget? desktopBottomAction;

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // LEFT PANEL (~43%): Navy/Teal brand gradient, logo, theme toggle, hero carousel
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
                    // Left Hero (Carousel or Custom)
                    Expanded(
                      child: desktopLeftHero ?? const AuthBrandingCarousel(),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // RIGHT PANEL (~57%): Surface background, full-height, centered form
          Expanded(
            flex: kAuthRightPanelFlex,
            child: Container(
              color: AppColors.surfaceOf(context),
              child: SafeArea(
                child: Column(
                  children: [
                    // Right panel header (Back / Help or custom)
                    if (rightHeader != null)
                      rightHeader!
                    else if (showBackButton ||
                        showHelpButton ||
                        onBack != null ||
                        onHelp != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (showBackButton || onBack != null)
                              IconButton(
                                icon: const Icon(Icons.arrow_back_rounded),
                                color: AppColors.textPrimaryOf(context),
                                tooltip: 'Back',
                                onPressed: onBack ??
                                    () => Navigator.of(context).maybePop(),
                              )
                            else
                              const SizedBox(width: 48),
                            if (showHelpButton || onHelp != null)
                              TextButton.icon(
                                onPressed: onHelp,
                                icon: Icon(
                                  Icons.help_outline_rounded,
                                  size: 18,
                                  color: AppColors.textSecondaryOf(context),
                                ),
                                label: Text(
                                  'Help',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondaryOf(context),
                                  ),
                                ),
                              )
                            else
                              const SizedBox(width: 48),
                          ],
                        ),
                      ),

                    // Centered scrollable form content
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 40,
                            vertical: 24,
                          ),
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          child: ConstrainedBox(
                            constraints:
                                BoxConstraints(maxWidth: formMaxWidth),
                            child: desktopForm,
                          ),
                        ),
                      ),
                    ),

                    // Optional pinned bottom action
                    if (desktopBottomAction != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(40, 8, 40, 24),
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints(maxWidth: formMaxWidth),
                          child: desktopBottomAction!,
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

/// Auto-advancing healthcare branding carousel for desktop left panel.
class AuthBrandingCarousel extends StatefulWidget {
  const AuthBrandingCarousel({
    super.key,
    this.slides = kDefaultAuthSlides,
  });

  final List<AuthLayoutSlideData> slides;

  @override
  State<AuthBrandingCarousel> createState() => _AuthBrandingCarouselState();
}

class _AuthBrandingCarouselState extends State<AuthBrandingCarousel> {
  final _pageController = PageController();
  int _currentSlide = 0;
  Timer? _carouselTimer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _carouselTimer?.cancel();
    _carouselTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_pageController.hasClients) return;
      final next = (_currentSlide + 1) % widget.slides.length;
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

  @override
  Widget build(BuildContext context) {
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
              itemCount: widget.slides.length,
              itemBuilder: (context, index) {
                final slide = widget.slides[index];
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.slides.length, (index) {
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
                    color: active
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
