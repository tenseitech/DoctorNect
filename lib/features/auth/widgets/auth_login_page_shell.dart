import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/layout/responsive_layout.dart';
import '../../../core/theme/app_colors.dart';
import '../../../widgets/required_field_label.dart';
import '../../../widgets/theme_toggle_button.dart';
import 'auth_login_branding.dart';
import 'auth_login_form_field.dart';

/// Legacy floating-label decoration (forgot-password flows, etc.).
InputDecoration authLoginInputDecoration({
  required BuildContext context,
  required Color accentColor,
  required String labelText,
  String? hintText,
  Widget? prefixIcon,
  Widget? suffixIcon,
  String? counterText,
  bool isRequired = false,
}) {
  return RequiredFieldLabels.decorate(
    authLoginFieldDecoration(
      context: context,
      accentColor: accentColor,
      hintText: hintText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      counterText: counterText,
    ),
    labelText,
    isRequired: isRequired,
  );
}

// ---------------------------------------------------------------------------
// Background painter – draws themed decorative shapes (circles, pills,
// rounded-rects, crosses / plus-signs) using the module accent colour at very
// low opacity so that they sit subtly behind the login form.
// ---------------------------------------------------------------------------
class _LoginBackgroundPainter extends CustomPainter {
  _LoginBackgroundPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(color.toARGB32()); // deterministic per-colour

    // ── helper paints ──
    Paint fill(double alpha) =>
        Paint()..color = color.withValues(alpha: alpha * 0.85);
    Paint stroke(double alpha, double w) => Paint()
      ..color = color.withValues(alpha: alpha * 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;

    // ── floating circles ──
    for (var i = 0; i < 14; i++) {
      final r = 12.0 + rng.nextDouble() * 60;
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final alpha = 0.08 + rng.nextDouble() * 0.07;
      canvas.drawCircle(Offset(x, y), r, fill(alpha));
    }

    // ── ring circles ──
    for (var i = 0; i < 6; i++) {
      final r = 30.0 + rng.nextDouble() * 70;
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      canvas.drawCircle(
          Offset(x, y), r, stroke(0.10 + rng.nextDouble() * 0.06, 2.2));
    }

    // ── pill / rounded-rects ──
    for (var i = 0; i < 8; i++) {
      final w = 24.0 + rng.nextDouble() * 50;
      final h = 10.0 + rng.nextDouble() * 20;
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final angle = rng.nextDouble() * math.pi;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: w, height: h),
            Radius.circular(h / 2)),
        fill(0.08 + rng.nextDouble() * 0.06),
      );
      canvas.restore();
    }

    // ── plus / cross signs ──
    for (var i = 0; i < 5; i++) {
      final arm = 10.0 + rng.nextDouble() * 22;
      final thick = 3.0 + rng.nextDouble() * 4;
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final p = fill(0.10 + rng.nextDouble() * 0.06);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(x, y), width: arm * 2, height: thick),
            Radius.circular(thick / 2)),
        p,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(x, y), width: thick, height: arm * 2),
            Radius.circular(thick / 2)),
        p,
      );
    }

    // ── small dots / particles ──
    for (var i = 0; i < 22; i++) {
      final r = 2.0 + rng.nextDouble() * 5;
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      canvas.drawCircle(Offset(x, y), r, fill(0.12 + rng.nextDouble() * 0.08));
    }
  }

  @override
  bool shouldRepaint(_LoginBackgroundPainter old) => old.color != color;
}


class AuthLoginPageShell extends StatelessWidget {
  const AuthLoginPageShell({
    super.key,
    required this.appBarTitle,
    required this.accentColor,
    required this.icon,
    required this.subtitle,
    required this.body,
    this.loading = false,
    this.welcomeTitle = 'Welcome Back',
    this.maxWidth = 480,
    this.branding,
  });

  final String appBarTitle;
  final Color accentColor;
  final IconData icon;
  final String subtitle;
  final Widget body;
  final bool loading;
  final String welcomeTitle;
  final double maxWidth;
  /// When set, uses split desktop + branded mobile layouts (login screens).
  final AuthLoginBranding? branding;

  bool _useSplit(BuildContext context) =>
      branding != null && ResponsiveLayout.screenWidth(context) >= 900;

  @override
  Widget build(BuildContext context) {
    if (_useSplit(context)) {
      return _SplitLoginScaffold(
        accentColor: accentColor,
        icon: icon,
        subtitle: subtitle,
        body: body,
        loading: loading,
        welcomeTitle: welcomeTitle,
        branding: branding!,
      );
    }
    if (branding != null && ResponsiveLayout.isCompact(context)) {
      return _MobileBrandedLoginScaffold(
        appBarTitle: appBarTitle,
        accentColor: accentColor,
        icon: icon,
        subtitle: subtitle,
        body: body,
        loading: loading,
        branding: branding!,
      );
    }
    return _StackedLoginScaffold(
      appBarTitle: appBarTitle,
      accentColor: accentColor,
      icon: icon,
      subtitle: subtitle,
      body: body,
      loading: loading,
      welcomeTitle: welcomeTitle,
      maxWidth: maxWidth,
    );
  }
}

// ---------------------------------------------------------------------------
// Desktop split layout — branding left, form right.
// ---------------------------------------------------------------------------
class _SplitLoginScaffold extends StatelessWidget {
  const _SplitLoginScaffold({
    required this.accentColor,
    required this.icon,
    required this.subtitle,
    required this.body,
    required this.loading,
    required this.welcomeTitle,
    required this.branding,
  });

  final Color accentColor;
  final IconData icon;
  final String subtitle;
  final Widget body;
  final bool loading;
  final String welcomeTitle;
  final AuthLoginBranding branding;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceOf(context),
      body: loading
          ? Center(child: CircularProgressIndicator(color: accentColor))
          : Stack(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 48,
                      child: _LoginBrandingPanel(
                        accentColor: accentColor,
                        icon: icon,
                        welcomeTitle: welcomeTitle,
                        subtitle: subtitle,
                        branding: branding,
                      ),
                    ),
                    Expanded(
                      flex: 52,
                      child: _LoginFormSide(
                        accentColor: accentColor,
                        body: body,
                        maxWidth: 400,
                      ),
                    ),
                  ],
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_rounded),
                          onPressed: () => Navigator.maybePop(context),
                          style: IconButton.styleFrom(foregroundColor: Colors.white),
                        ),
                        const ThemeToggleButton(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _LoginBrandingPanel extends StatelessWidget {
  const _LoginBrandingPanel({
    required this.accentColor,
    required this.icon,
    required this.welcomeTitle,
    required this.subtitle,
    required this.branding,
  });

  final Color accentColor;
  final IconData icon;
  final String welcomeTitle;
  final String subtitle;
  final AuthLoginBranding branding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor,
            branding.gradientEnd(accentColor),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _LoginBackgroundPainter(color: AppColors.surfaceOf(context).withValues(alpha: 0.15)),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(48, 40, 48, 40),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                              ),
                              child: Icon(icon, color: Colors.white, size: 24),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                'DoctorNect',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: -0.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 40),
                        Text(
                          welcomeTitle,
                          style: GoogleFonts.inter(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.15,
                            letterSpacing: -0.8,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          subtitle,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            color: Colors.white.withValues(alpha: 0.92),
                            height: 1.55,
                          ),
                        ),
                        const SizedBox(height: 32),
                        ...branding.features.map((f) => Padding(
                              padding: const EdgeInsets.only(bottom: 18),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(f.icon, color: Colors.white, size: 20),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          f.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white,
                                          ),
                                        ),
                                        Text(
                                          f.subtitle,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.inter(
                                            fontSize: 13,
                                            color: Colors.white.withValues(alpha: 0.85),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            )),
                        const SizedBox(height: 32),
                        Row(
                          children: [
                            Icon(Icons.verified_user_outlined, size: 16, color: Colors.white.withValues(alpha: 0.8)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                branding.footerNote,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginFormSide extends StatelessWidget {
  const _LoginFormSide({
    required this.accentColor,
    required this.body,
    this.maxWidth = 440,
  });

  final Color accentColor;
  final Widget body;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 32),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: _AuthLoginFormCard(
              accentColor: accentColor,
              compact: false,
              flat: true,
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Branded mobile header + form card (login screens).
// ---------------------------------------------------------------------------
class _MobileBrandedLoginScaffold extends StatelessWidget {
  const _MobileBrandedLoginScaffold({
    required this.appBarTitle,
    required this.accentColor,
    required this.icon,
    required this.subtitle,
    required this.body,
    required this.loading,
    required this.branding,
  });

  final String appBarTitle;
  final Color accentColor;
  final IconData icon;
  final String subtitle;
  final Widget body;
  final bool loading;
  final AuthLoginBranding branding;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      resizeToAvoidBottomInset: true,
      body: loading
          ? Center(child: CircularProgressIndicator(color: accentColor))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MobileBrandedLoginHeader(
                  accentColor: accentColor,
                  icon: icon,
                  title: appBarTitle,
                  subtitle: subtitle,
                  branding: branding,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      20,
                      16,
                      24 + MediaQuery.viewInsetsOf(context).bottom,
                    ),
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    child: _AuthLoginFormCard(
                      accentColor: accentColor,
                      compact: true,
                      child: body,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _MobileBrandedLoginHeader extends StatelessWidget {
  const _MobileBrandedLoginHeader({
    required this.accentColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.branding,
  });

  final Color accentColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final AuthLoginBranding branding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accentColor, branding.gradientEnd(accentColor)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 20, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.maybePop(context),
                      style: IconButton.styleFrom(foregroundColor: Colors.white),
                    ),
                    const ThemeToggleButton(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                      ),
                      child: Icon(icon, color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.92),
                              height: 1.4,
                            ),
                          ),
                        ],
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
}

// ---------------------------------------------------------------------------
// Mobile / tablet stacked layout.
// ---------------------------------------------------------------------------
class _StackedLoginScaffold extends StatelessWidget {
  const _StackedLoginScaffold({
    required this.appBarTitle,
    required this.accentColor,
    required this.icon,
    required this.subtitle,
    required this.body,
    required this.loading,
    required this.welcomeTitle,
    required this.maxWidth,
  });

  final String appBarTitle;
  final Color accentColor;
  final IconData icon;
  final String subtitle;
  final Widget body;
  final bool loading;
  final String welcomeTitle;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final compact = ResponsiveLayout.isCompact(context);
    final isMedium = ResponsiveLayout.isMedium(context);
    final backgroundGradient = LinearGradient(
      colors: [
        accentColor.withValues(alpha: compact ? 0.10 : 0.14),
        const Color(0xFFF8FAFC),
        Colors.white,
      ],
      stops: const [0.0, 0.45, 1.0],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );

    final horizontalPadding = compact ? 16.0 : 24.0;
    final formMaxWidth = isMedium ? 480.0 : (compact ? double.infinity : maxWidth);

    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: AppBar(
        title: Text(
          appBarTitle,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimaryOf(context),
            fontSize: compact ? 16 : 17,
          ),
        ),
        centerTitle: true,
        actions: const [
          ThemeToggleButton(),
          SizedBox(width: 8),
        ],
        backgroundColor: AppColors.surfaceOf(context),
        foregroundColor: AppColors.textPrimaryOf(context),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.borderOf(context)),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: backgroundGradient),
        child: loading
            ? Center(child: CircularProgressIndicator(color: accentColor))
            : SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      compact ? 12 : 20,
                      horizontalPadding,
                      compact ? 24 : 32,
                    ),
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: formMaxWidth),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (compact) ...[
                            Center(
                              child: Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceOf(context),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: accentColor.withValues(alpha: 0.12)),
                                ),
                                child: Icon(icon, color: accentColor, size: 28),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          Text(
                            welcomeTitle,
                            textAlign: compact ? TextAlign.center : TextAlign.left,
                            style: GoogleFonts.inter(
                              fontSize: compact ? 22 : 24,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimaryOf(context),
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            subtitle,
                            textAlign: compact ? TextAlign.center : TextAlign.left,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: AppColors.textSecondaryOf(context),
                              height: 1.45,
                            ),
                          ),
                          SizedBox(height: compact ? 20 : 24),
                          _AuthLoginFormCard(
                            accentColor: accentColor,
                            compact: compact,
                            child: body,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _AuthLoginFormCard extends StatelessWidget {
  const _AuthLoginFormCard({
    required this.accentColor,
    required this.compact,
    required this.child,
    this.flat = false,
  });

  final Color accentColor;
  final bool compact;
  final Widget child;
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final radius = compact ? 16.0 : 18.0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.borderOf(context)),
        boxShadow: flat
            ? null
            : [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.06),
                  blurRadius: compact ? 20 : 28,
                  offset: Offset(0, compact ? 8 : 12),
                ),
              ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 3,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accentColor,
                  accentColor.withValues(alpha: 0.45),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 18 : 24,
              compact ? 20 : 24,
              compact ? 18 : 24,
              compact ? 22 : 26,
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

class AuthLoginDividerLabel extends StatelessWidget {
  const AuthLoginDividerLabel({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: AppColors.borderOf(context), height: 1)),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
          ),
        ),
        Expanded(child: Divider(color: AppColors.borderOf(context), height: 1)),
      ],
    );
  }
}

class AuthLoginPrimaryButton extends StatelessWidget {
  const AuthLoginPrimaryButton({
    super.key,
    required this.accentColor,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.loadingText,
  });

  final Color accentColor;
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final String? loadingText;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.28),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: accentColor,
          disabledBackgroundColor: accentColor.withValues(alpha: 0.55),
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: loading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                  ),
                  if (loadingText != null && loadingText!.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        loadingText!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, size: 18, color: Colors.white),
                ],
              ),
      ),
    );
  }
}

class AuthLoginRegisterButton extends StatelessWidget {
  const AuthLoginRegisterButton({
    super.key,
    required this.accentColor,
    required this.label,
    required this.onPressed,
  });

  final Color accentColor;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accentColor.withValues(alpha: 0.14)),
      ),
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: BorderSide.none,
          backgroundColor: Colors.transparent,
          minimumSize: const Size(double.infinity, 50),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_add_alt_1_outlined, color: accentColor, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: accentColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
