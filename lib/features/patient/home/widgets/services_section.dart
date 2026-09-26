import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/ambulance_icons.dart';
import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/patient_mock_data.dart';
import 'package:medibond/features/patient/models/patient_models.dart';
import '../../../../core/theme/app_typography.dart';

class ServicesSection extends StatelessWidget {
  const ServicesSection({
    super.key,
    required this.onServiceTap,
  });

  final ValueChanged<ServiceItem> onServiceTap;

  static const _wideBreakpoint = 600.0;

  @override
  Widget build(BuildContext context) {
    final services = PatientMockData.services;
    final isWide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isWide ? 20 : 16,
        isWide ? 20 : 12,
        isWide ? 20 : 16,
        isWide ? 20 : 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Services',
            style: GoogleFonts.inter(
              fontSize: isWide ? 17 : 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
          SizedBox(height: isWide ? 14 : 10),
          if (isWide)
            Row(
              children: [
                for (var i = 0; i < services.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(
                    child: _ServiceTile(
                      service: services[i],
                      style: _ServiceStyle.forRoute(services[i].route),
                      onTap: () => onServiceTap(services[i]),
                    ),
                  ),
                ],
              ],
            )
          else
            Row(
              children: [
                for (var i = 0; i < services.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _ServiceTile(
                      service: services[i],
                      style: _ServiceStyle.forRoute(services[i].route),
                      mobileColumn: true,
                      onTap: () => onServiceTap(services[i]),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _ServiceStyle {
  const _ServiceStyle({
    required this.gradient,
    required this.subtitle,
  });

  final List<Color> gradient;
  final String subtitle;

  static _ServiceStyle forRoute(String route) {
    return switch (route) {
      'records' => const _ServiceStyle(
          gradient: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
          subtitle: 'Health records',
        ),
      'sos' => const _ServiceStyle(
          gradient: [Color(0xFFDC2626), Color(0xFFB91C1C)],
          subtitle: 'Emergency help',
        ),
      'digital-pass' => const _ServiceStyle(
          gradient: [Color(0xFF0D9488), Color(0xFF0369A1)],
          subtitle: 'Digital ID pass',
        ),
      'near-you' => const _ServiceStyle(
          gradient: [Color(0xFF0D9488), Color(0xFF0369A1)],
          subtitle: 'Dr. in city',
        ),
      'my-lab' => const _ServiceStyle(
          gradient: [Color(0xFF7C3AED), Color(0xFF6D28D9)],
          subtitle: 'Saved labs',
        ),
      'appointments' => const _ServiceStyle(
          gradient: [Color(0xFFEA580C), Color(0xFFC2410C)],
          subtitle: 'Upcoming visits',
        ),
      'ambulance' => const _ServiceStyle(
          gradient: [Color(0xFFDC2626), Color(0xFFB91C1C)],
          subtitle: 'Emergency help',
        ),
      _ => const _ServiceStyle(
          gradient: [Color(0xFF0D9488), Color(0xFF0369A1)],
          subtitle: 'Open service',
        ),
    };
  }
}

class _ServiceTile extends StatefulWidget {
  const _ServiceTile({
    required this.service,
    required this.style,
    required this.onTap,
    this.mobileColumn = false,
  });

  final ServiceItem service;
  final _ServiceStyle style;
  final VoidCallback onTap;
  final bool mobileColumn;

  @override
  State<_ServiceTile> createState() => _ServiceTileState();
}

class _ServiceTileState extends State<_ServiceTile> {
  bool _pressed = false;

  String get _shortLabel {
    return switch (widget.service.route) {
      'records' => 'Records',
      'sos' => 'SOS',
      'digital-pass' => 'Pass',
      'near-you' => 'Citywide',
      'my-lab' => 'My Lab',
      'appointments' => 'Appointment',
      'ambulance' => 'Ambulance',
      _ => widget.service.label,
    };
  }

  String get _label {
    if (widget.mobileColumn) return _shortLabel;
    if (ResponsiveLayout.isExpanded(context)) return widget.service.label;
    return _shortLabel;
  }

  String? get _assetPath =>
      widget.service.assetPath ??
      switch (widget.service.route) {
        'records' => 'assets/images/services/records.png',
        'sos' => 'assets/images/services/sos.png',
        'digital-pass' => 'assets/icons/common/digital_pass.png',
        _ => null,
      };

  Widget _serviceIcon(double size) {
    if (_assetPath != null) {
      return Image.asset(
        _assetPath!,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
            Icon(widget.service.icon, size: size, color: AppColors.white),
      );
    }
    if (widget.service.route == 'ambulance') {
      return AmbulanceWithPlusIcon(size: size);
    }
    return Icon(widget.service.icon, size: size, color: AppColors.white);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mobileColumn) {
      return _buildMobileColumnTile();
    }

    const iconSize = 22.0;
    const boxSize = 46.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        onHighlightChanged: (value) => setState(() => _pressed = value),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: _pressed
                ? widget.style.gradient.first.withValues(alpha: 0.06)
                : AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _pressed
                  ? widget.style.gradient.first.withValues(alpha: 0.35)
                  : AppColors.borderOf(context),
            ),
          ),
          child: Row(
            children: [
              if (_assetPath != null)
                SizedBox(
                  width: boxSize,
                  height: boxSize,
                  child: Image.asset(
                    _assetPath!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      width: boxSize,
                      height: boxSize,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: widget.style.gradient,
                        ),
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: [
                          BoxShadow(
                            color: widget.style.gradient.last
                                .withValues(alpha: 0.24),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(widget.service.icon,
                            size: iconSize, color: AppColors.white),
                      ),
                    ),
                  ),
                )
              else
                Container(
                  width: boxSize,
                  height: boxSize,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: widget.style.gradient,
                    ),
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: [
                      BoxShadow(
                        color:
                            widget.style.gradient.last.withValues(alpha: 0.24),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(child: _serviceIcon(iconSize)),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodySmall,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.style.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.labelSmall,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color:
                    AppColors.textSecondaryOf(context).withValues(alpha: 0.8),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileColumnTile() {
    const iconBox = 44.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        onHighlightChanged: (value) => setState(() => _pressed = value),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: _pressed
                ? widget.style.gradient.first.withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_assetPath != null)
                SizedBox(
                  width: iconBox,
                  height: iconBox,
                  child: Image.asset(
                    _assetPath!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      width: iconBox,
                      height: iconBox,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: widget.style.gradient,
                        ),
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: [
                          BoxShadow(
                            color: widget.style.gradient.last
                                .withValues(alpha: 0.24),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(widget.service.icon,
                            size: 20, color: AppColors.white),
                      ),
                    ),
                  ),
                )
              else
                Container(
                  width: iconBox,
                  height: iconBox,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: widget.style.gradient,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color:
                            widget.style.gradient.last.withValues(alpha: 0.24),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(child: _serviceIcon(20)),
                ),
              const SizedBox(height: 6),
              Text(
                _label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
