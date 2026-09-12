import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_colors.dart';
import 'package:medibond/features/patient/models/patient_models.dart';

typedef HomeCarouselCtaHandler = void Function(String? route);

class HomeBannerCarousel extends StatefulWidget {
  const HomeBannerCarousel({
    super.key,
    required this.items,
    required this.dotActiveColor,
    this.onCtaTap,
  });

  final List<HomeCarouselItem> items;
  final Color dotActiveColor;
  final HomeCarouselCtaHandler? onCtaTap;

  @override
  State<HomeBannerCarousel> createState() => _HomeBannerCarouselState();
}

class _HomeBannerCarouselState extends State<HomeBannerCarousel> {
  static const _autoScrollInterval = Duration(seconds: 5);
  static const _wideBreakpoint = 600.0;
  static const _wideNavGutter = 52.0;

  int _index = 0;
  late final PageController _controller;
  Timer? _autoTimer;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    final initialPage = widget.items.isNotEmpty ? widget.items.length * 1000 : 0;
    _controller = PageController(initialPage: initialPage);
    _startAutoScroll();
  }

  void _startAutoScroll() {
    if (_isHovered) return;
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(_autoScrollInterval, (_) {
      if (!mounted || _isHovered) return;
      _step(1);
    });
  }

  void _pauseAutoScroll() {
    _autoTimer?.cancel();
    _autoTimer = null;
  }

  void _onHoverEnter() {
    if (_isHovered) return;
    _isHovered = true;
    _pauseAutoScroll();
  }

  void _onHoverExit() {
    if (!_isHovered) return;
    _isHovered = false;
    _startAutoScroll();
  }

  void _step(int delta) {
    if (widget.items.isEmpty || !_controller.hasClients) return;
    final currentPage = _controller.page?.round() ?? (widget.items.length * 1000);
    _controller.animateToPage(
      currentPage + delta,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    final isWide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4);
    final height = (isWide ? 220.0 : 120.0) * textScale;
    final borderRadius = isWide ? 0.0 : AppConstants.cardRadius.toDouble();

    return MouseRegion(
      onEnter: (_) => _onHoverEnter(),
      onExit: (_) => _onHoverExit(),
      child: Column(
        children: [
          SizedBox(
            height: height,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PageView.builder(
                  controller: _controller,
                  onPageChanged: (i) => setState(() => _index = i % widget.items.length),
                  itemBuilder: (_, index) {
                    final actualIndex = index % widget.items.length;
                    return _HomeBannerCarouselSlide(
                      item: widget.items[actualIndex],
                      isWide: isWide,
                      borderRadius: borderRadius,
                      contentHorizontalInset: isWide ? _wideNavGutter : 0,
                      onCtaTap: widget.onCtaTap,
                    );
                  },
                ),
                if (isWide) ...[
                  Positioned(
                    left: 12,
                    child: _CarouselNavButton(
                      icon: Icons.chevron_left,
                      onTap: () {
                        _step(-1);
                        if (!_isHovered) _startAutoScroll();
                      },
                    ),
                  ),
                  Positioned(
                    right: 12,
                    child: _CarouselNavButton(
                      icon: Icons.chevron_right,
                      onTap: () {
                        _step(1);
                        if (!_isHovered) _startAutoScroll();
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.items.length, (i) {
              return Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _index == i ? widget.dotActiveColor : AppColors.borderOf(context),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _CarouselNavButton extends StatelessWidget {
  const _CarouselNavButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceOf(context),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      shape: CircleBorder(side: BorderSide(color: Colors.grey.shade300)),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 22, color: AppColors.textPrimaryOf(context)),
        ),
      ),
    );
  }
}

class _HomeBannerCarouselSlide extends StatelessWidget {
  const _HomeBannerCarouselSlide({
    required this.item,
    required this.isWide,
    required this.borderRadius,
    this.contentHorizontalInset = 0,
    this.onCtaTap,
  });

  final HomeCarouselItem item;
  final bool isWide;
  final double borderRadius;
  final double contentHorizontalInset;
  final HomeCarouselCtaHandler? onCtaTap;

  PromoBanner get banner => item.banner;

  @override
  Widget build(BuildContext context) {
    if (isWide) {
      return _buildWebBanner(context);
    }
    return _buildMobileBanner(context);
  }

  Widget _buildMobileBanner(BuildContext context) {
    final isTip = banner.kind == HomeCarouselKind.healthTip;
    final badgeColor = isTip
        ? const Color(0xFF16A34A)
        : (banner.gradientColors.isNotEmpty
            ? banner.gradientColors.first
            : const Color(0xFF2563EB));

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: item.ctaRoute != null && onCtaTap != null
              ? () => onCtaTap!(item.ctaRoute)
              : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
          _gradientBackground(begin: Alignment.topLeft, end: Alignment.bottomRight),
          if (banner.imageUrl != null && banner.imageUrl!.isNotEmpty)
            Image.network(banner.imageUrl!, fit: BoxFit.cover),
          if (banner.icon != null && (banner.imageUrl == null || banner.imageUrl!.isEmpty))
            Positioned(
              right: -8,
              bottom: -12,
              child: Icon(
                banner.icon,
                size: 72,
                color: AppColors.surfaceOf(context).withValues(alpha: 0.18),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.05),
                  Colors.black.withValues(alpha: 0.55),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BadgeChip(label: banner.badgeLabel, color: badgeColor),
                const Spacer(),
                Text(
                  banner.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  banner.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    height: 1.3,
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
              ],
            ),
          ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebBanner(BuildContext context) {
    final isTip = banner.kind == HomeCarouselKind.healthTip;
    final badgeColor = isTip
        ? const Color(0xFF16A34A)
        : (banner.gradientColors.isNotEmpty
            ? banner.gradientColors.first
            : const Color(0xFF2563EB));

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _gradientBackground(begin: Alignment.centerLeft, end: Alignment.centerRight),
          if (banner.imageUrl != null && banner.imageUrl!.isNotEmpty)
            Image.network(banner.imageUrl!, fit: BoxFit.cover),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: contentHorizontalInset),
            child: Row(
              children: [
                Expanded(
                  flex: 6,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 24, 16, 24),
                    child: SingleChildScrollView(
                      physics: const NeverScrollableScrollPhysics(),
                      child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                      _BadgeChip(label: banner.badgeLabel, color: badgeColor),
                      const SizedBox(height: 14),
                      Text(
                        banner.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        banner.subtitle,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          height: 1.4,
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                      ),
                      if (item.ctaLabel != null) ...[
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: item.ctaRoute != null && onCtaTap != null
                              ? () => onCtaTap!(item.ctaRoute)
                              : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: banner.gradientColors.first,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            item.ctaLabel!,
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 4,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.05),
                        Colors.white.withValues(alpha: 0.22),
                      ],
                    ),
                  ),
                  child: banner.icon != null
                      ? Icon(
                          banner.icon,
                          size: 120,
                          color: Colors.white.withValues(alpha: 0.35),
                        )
                      : null,
                ),
              ),
            ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gradientBackground({
    required Alignment begin,
    required Alignment end,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: begin,
          end: end,
          colors: banner.gradientColors,
        ),
      ),
    );
  }
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
