import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/enums/user_type.dart';
import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/notifications/app_notification.dart';
import '../../../../core/notifications/widgets/notification_bell_button.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/doctor_models.dart';
import '../../profile/data/doctor_profile_store.dart';
import '../../widgets/doctor_profile_avatar_button.dart';
import '../../../../widgets/header_overflow_menu.dart';
import '../../../../widgets/theme_toggle_button.dart';
import '../../../../core/theme/app_typography.dart';

class DoctorHomeTopBar extends StatelessWidget {
  const DoctorHomeTopBar({
    super.key,
    required this.displayName,
    required this.verificationStatus,
  });

  final String displayName;
  final VerificationStatus verificationStatus;

  @override
  Widget build(BuildContext context) {
    final compact = ResponsiveLayout.isCompact(context);
    final rawName = displayName.trim();
    final cleanName = rawName.isEmpty ? 'Doctor' : rawName;
    final greetingText = (cleanName.toLowerCase().startsWith('dr.') ||
            cleanName.toLowerCase().startsWith('dr '))
        ? 'Hi, $cleanName'
        : 'Hi, Dr. $cleanName';
    final verified = verificationStatus == VerificationStatus.verified;

    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(compact ? 16 : 20, compact ? 6 : 12,
              compact ? 16 : 20, compact ? 6 : 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const DoctorProfileAvatarButton(),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        greetingText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: compact ? 16 : 20,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _DoctorVerificationBadge(
                        verified: verified, compact: compact),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const ThemeToggleButton(),
              const SizedBox(width: 2),
              const NotificationBellButton(
                  audience: NotificationAudience.doctor),
              const HeaderOverflowMenu(userType: UserType.doctor),
            ],
          ),
        ),
      ),
    );
  }
}

class _DoctorVerificationBadge extends StatelessWidget {
  const _DoctorVerificationBadge({
    required this.verified,
    required this.compact,
  });

  final bool verified;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final accent = verified ? const Color(0xFF16A34A) : const Color(0xFFEA580C);

    return InkWell(
      onTap: () => _showKycDetailsSheet(context, verified),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(
          verified ? Icons.verified_rounded : Icons.hourglass_top_rounded,
          size: compact ? 18 : 20,
          color: accent,
        ),
      ),
    );
  }

  void _showKycDetailsSheet(BuildContext context, bool verified) {
    final profile = DoctorProfileStore.instance.profile;
    final accent = verified ? const Color(0xFF16A34A) : const Color(0xFFEA580C);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: AppColors.borderOf(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    verified
                        ? Icons.verified_rounded
                        : Icons.hourglass_top_rounded,
                    color: accent,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        verified
                            ? 'Verified Doctor Account'
                            : 'Verification Under Review',
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.headlineSmall,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimaryOf(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        verified
                            ? 'Medical Council Credentials Confirmed'
                            : 'KYC Verification Pending Admin Approval',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Divider(height: 1),
            const SizedBox(height: 14),
            _KycInfoRow(
                label: 'Doctor Name',
                value: profile.fullName.isEmpty ? 'Not set' : profile.fullName),
            const SizedBox(height: 10),
            _KycInfoRow(
                label: 'Council Reg. Number',
                value: profile.councilNumber.isEmpty
                    ? 'Pending'
                    : profile.councilNumber),
            const SizedBox(height: 10),
            _KycInfoRow(
                label: 'State Medical Council',
                value: profile.stateCouncil.isEmpty
                    ? 'Pending'
                    : profile.stateCouncil),
            const SizedBox(height: 10),
            _KycInfoRow(
                label: 'Specialization',
                value: profile.specialization.isEmpty
                    ? 'General'
                    : profile.specialization),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.cardBgOf(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.borderOf(context)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 18, color: AppColors.doctorBlue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      verified
                          ? 'Your medical registration & credentials are fully verified. All clinical features & prescription signing are active.'
                          : 'Your registration credentials are currently being cross-referenced with State Medical Council records.',
                      style: GoogleFonts.inter(
                          fontSize: AppTypography.labelMedium,
                          color: AppColors.textSecondaryOf(context),
                          height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.doctorBlue,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

class _KycInfoRow extends StatelessWidget {
  const _KycInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
              fontSize: AppTypography.bodySmall,
              color: AppColors.textSecondaryOf(context),
              fontWeight: FontWeight.w500),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
                fontSize: AppTypography.bodySmall,
                color: AppColors.textPrimaryOf(context),
                fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class DoctorHomeStatItem {
  const DoctorHomeStatItem({
    required this.label,
    required this.value,
    required this.gradient,
    required this.icon,
    required this.onTap,
    this.assetPath,
  });

  final String label;
  final String value;
  final List<Color> gradient;
  final IconData icon;
  final VoidCallback onTap;
  final String? assetPath;
}

class DoctorHomeStatsStrip extends StatelessWidget {
  const DoctorHomeStatsStrip({
    super.key,
    required this.items,
    required this.selectedDate,
    required this.onCalendarTap,
    this.onSearchTap,
  });

  final List<DoctorHomeStatItem> items;
  final DateTime selectedDate;
  final VoidCallback onCalendarTap;
  final VoidCallback? onSearchTap;

  static const _statsHeightRegular = 124.0;

  static BoxDecoration _elevatedCard(BuildContext context) {
    return BoxDecoration(
      color: AppColors.surfaceOf(context),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
          color: AppColors.borderOf(context).withValues(alpha: 0.55)),
      boxShadow: [
        BoxShadow(
          color: AppColors.isDark(context)
              ? Colors.black.withValues(alpha: 0.3)
              : AppColors.doctorBlue.withValues(alpha: 0.06),
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: AppColors.isDark(context)
              ? Colors.black.withValues(alpha: 0.2)
              : AppColors.textPrimary.withValues(alpha: 0.03),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final compact = ResponsiveLayout.isCompact(context);

    return ColoredBox(
      color: AppColors.cardBgOf(context),
      child: Padding(
        padding: EdgeInsets.fromLTRB(compact ? 16 : 20, compact ? 4 : 10,
            compact ? 16 : 20, compact ? 6 : 16),
        child: compact
            ? _buildMobileLayout(context)
            : _buildDesktopLayout(context),
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Container(
      decoration: _elevatedCard(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 68),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    Expanded(
                      child: _DoctorStatTile(
                        item: items[i],
                        compact: true,
                        mobileStripMode: true,
                      ),
                    ),
                    if (i < items.length - 1)
                      Container(
                        width: 1,
                        height: 40,
                        color:
                            AppColors.borderOf(context).withValues(alpha: 0.85),
                      ),
                  ],
                ],
              ),
            ),
            if (onSearchTap != null) ...[
              Container(
                  height: 1,
                  color: AppColors.borderOf(context).withValues(alpha: 0.85)),
              _DoctorMobileInlineSearch(onTap: onSearchTap!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    const statsHeight = _statsHeightRegular;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SizedBox(
            height: statsHeight,
            child: Container(
              decoration: _elevatedCard(context),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Row(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      Expanded(
                        child: _DoctorStatTile(
                          item: items[i],
                          compact: false,
                        ),
                      ),
                      if (i < items.length - 1)
                        Container(
                          width: 1,
                          height: statsHeight,
                          color: AppColors.borderOf(context)
                              .withValues(alpha: 0.85),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DoctorStatTile extends StatelessWidget {
  const _DoctorStatTile({
    required this.item,
    required this.compact,
    this.mobileStripMode = false,
  });

  final DoctorHomeStatItem item;
  final bool compact;
  final bool mobileStripMode;

  String get _label {
    if (!compact || mobileStripMode) {
      if (!mobileStripMode) return item.label;
      return switch (item.label) {
        'Completed' => 'Done',
        'Pending' => 'Pending',
        _ => item.label,
      };
    }
    return switch (item.label) {
      'Completed' => 'Done',
      _ => item.label,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (mobileStripMode) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: item.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (item.assetPath != null)
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Image.asset(
                      item.assetPath!,
                      width: 24,
                      height: 24,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: item.gradient,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(item.icon, size: 13, color: Colors.white),
                      ),
                    ),
                  )
                else
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: item.gradient,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(item.icon, size: 13, color: Colors.white),
                  ),
                const SizedBox(height: 3),
                Text(
                  item.value,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.bodyLarge,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimaryOf(context),
                    height: 1,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  _label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondaryOf(context),
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final iconSize = compact ? 32.0 : 40.0;
    final iconGlyph = compact ? 16.0 : 19.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 2 : 4,
            vertical: compact ? 8 : 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (item.assetPath != null)
                SizedBox(
                  width: iconSize,
                  height: iconSize,
                  child: Image.asset(
                    item.assetPath!,
                    width: iconSize,
                    height: iconSize,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      width: iconSize,
                      height: iconSize,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: item.gradient,
                        ),
                        borderRadius: BorderRadius.circular(compact ? 10 : 12),
                        boxShadow: [
                          BoxShadow(
                            color: item.gradient.last.withValues(alpha: 0.28),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child:
                          Icon(item.icon, size: iconGlyph, color: Colors.white),
                    ),
                  ),
                )
              else
                Container(
                  width: iconSize,
                  height: iconSize,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: item.gradient,
                    ),
                    borderRadius: BorderRadius.circular(compact ? 10 : 12),
                    boxShadow: [
                      BoxShadow(
                        color: item.gradient.last.withValues(alpha: 0.28),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(item.icon, size: iconGlyph, color: Colors.white),
                ),
              SizedBox(height: compact ? 6 : 9),
              Text(
                item.value,
                style: GoogleFonts.inter(
                  fontSize: compact ? 20 : 26,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimaryOf(context),
                  height: 1,
                  letterSpacing: -0.8,
                ),
              ),
              SizedBox(height: compact ? 2 : 4),
              Text(
                _label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: compact ? 10 : 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondaryOf(context),
                  height: 1,
                  letterSpacing: 0.05,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DoctorMobileInlineSearch extends StatelessWidget {
  const _DoctorMobileInlineSearch({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Container(
            height: 42,
            padding: EdgeInsets.only(left: 12, right: 4),
            decoration: BoxDecoration(
              color: AppColors.cardBgOf(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderOf(context)),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded,
                    color: AppColors.textSecondaryOf(context), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Search for patient, medical, lab and ambulance',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        fontSize: AppTypography.bodySmall,
                        color: AppColors.textSecondaryOf(context)),
                  ),
                ),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.doctorBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.arrow_forward_rounded,
                      color: AppColors.doctorBlue, size: 18),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DoctorHomePatientSearchBar extends StatelessWidget {
  const DoctorHomePatientSearchBar({
    super.key,
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final compact = ResponsiveLayout.isCompact(context);

    return ColoredBox(
      color: AppColors.surfaceOf(context),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            compact ? 16 : 20, 0, compact ? 16 : 20, compact ? 12 : 14),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Ink(
              height: compact ? 50 : 54,
              padding: EdgeInsets.only(
                  left: compact ? 14 : 16, right: compact ? 6 : 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceOf(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderOf(context)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.textPrimaryOf(context)
                        .withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    color: AppColors.textSecondaryOf(context),
                    size: 22,
                  ),
                  SizedBox(width: compact ? 10 : 12),
                  Expanded(
                    child: Text(
                      compact
                          ? 'Search for patient, medical, lab and ambulance'
                          : 'Search for patient, medical, lab and ambulance',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: compact ? 14 : 15,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                  ),
                  Container(
                    width: compact ? 38 : 42,
                    height: compact ? 38 : 42,
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      color: AppColors.doctorBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.arrow_forward_rounded,
                      color: AppColors.doctorBlue,
                      size: 20,
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

class DoctorHomeServiceItem {
  const DoctorHomeServiceItem({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.onTap,
    this.shortLabel,
    this.assetPath,
  });

  final String label;
  final String? shortLabel;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback onTap;
  final String? assetPath;
}

class DoctorHomeServicesSection extends StatefulWidget {
  const DoctorHomeServicesSection({
    super.key,
    required this.title,
    required this.services,
  });

  final String title;
  final List<DoctorHomeServiceItem> services;

  @override
  State<DoctorHomeServicesSection> createState() =>
      _DoctorHomeServicesSectionState();
}

class _DoctorHomeServicesSectionState extends State<DoctorHomeServicesSection> {
  void _openDrawer() {
    ClinicalToolsDrawer.show(
      context,
      title: widget.title,
      services: widget.services,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = !ResponsiveLayout.isCompact(context);
    final maxInline = isWide ? 4 : 3;
    final hasOverflow = widget.services.length > maxInline;

    return ColoredBox(
      color: AppColors.cardBgOf(context),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isWide ? 20 : 16,
          isWide ? 20 : 14,
          isWide ? 20 : 16,
          isWide ? 20 : 14,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.title,
                  style: GoogleFonts.inter(
                    fontSize: isWide ? 17 : 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
                if (hasOverflow)
                  InkWell(
                    onTap: _openDrawer,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Show all (${widget.services.length})',
                            style: GoogleFonts.inter(
                              fontSize: AppTypography.labelMedium,
                              fontWeight: FontWeight.w600,
                              color: AppColors.doctorBlue,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.keyboard_arrow_right_rounded,
                            size: 16,
                            color: AppColors.doctorBlue,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: isWide ? 14 : 10),
            isWide ? _buildWideCollapsed() : _buildMobileCollapsed(),
          ],
        ),
      ),
    );
  }

  Widget _buildWideCollapsed() {
    final maxVisible = widget.services.length > 4 ? 4 : widget.services.length;
    final hasOverflow = widget.services.length > 4;

    return Row(
      children: [
        for (var i = 0; i < maxVisible; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: _DoctorServiceTile(
              service: widget.services[i],
              onTap: widget.services[i].onTap,
            ),
          ),
        ],
        if (hasOverflow) ...[
          const SizedBox(width: 10),
          Expanded(
            child: _ShowMoreTile(
              label: 'Show more',
              subtitle: '+${widget.services.length - 4} tools',
              icon: Icons.grid_view_rounded,
              onTap: _openDrawer,
            ),
          ),
        ],
        for (var k = 0; k < (4 - maxVisible); k++) ...[
          const SizedBox(width: 10),
          const Expanded(child: SizedBox.shrink()),
        ],
      ],
    );
  }

  Widget _buildMobileCollapsed() {
    final showCount = widget.services.length > 3 ? 3 : widget.services.length;
    final hasOverflow = widget.services.length > 3;

    return Row(
      children: [
        for (var i = 0; i < showCount; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _DoctorServiceTile(
              service: widget.services[i],
              mobileColumn: true,
              onTap: widget.services[i].onTap,
            ),
          ),
        ],
        if (hasOverflow) ...[
          const SizedBox(width: 8),
          Expanded(
            child: _ShowMoreTile(
              label: 'See more',
              subtitle: '+${widget.services.length - 3}',
              icon: Icons.grid_view_rounded,
              mobileColumn: true,
              onTap: _openDrawer,
            ),
          ),
        ],
        for (var k = 0; k < (3 - showCount); k++) ...[
          const SizedBox(width: 8),
          const Expanded(child: SizedBox.shrink()),
        ],
      ],
    );
  }
}

class _ShowMoreTile extends StatefulWidget {
  const _ShowMoreTile({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.mobileColumn = false,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool mobileColumn;

  @override
  State<_ShowMoreTile> createState() => _ShowMoreTileState();
}

class _ShowMoreTileState extends State<_ShowMoreTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final gradient = [AppColors.doctorBlue, const Color(0xFF2563EB)];

    if (widget.mobileColumn) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (val) => setState(() => _pressed = val),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: _pressed
                  ? AppColors.doctorBlue.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradient,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.doctorBlue.withValues(alpha: 0.25),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(widget.icon, size: 20, color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                    color: AppColors.doctorBlue,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        onHighlightChanged: (val) => setState(() => _pressed = val),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: _pressed
                ? AppColors.doctorBlue.withValues(alpha: 0.12)
                : AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _pressed
                  ? AppColors.doctorBlue.withValues(alpha: 0.5)
                  : AppColors.doctorBlue.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradient,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.doctorBlue.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(widget.icon, size: 22, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodySmall,
                        fontWeight: FontWeight.w700,
                        color: AppColors.doctorBlue,
                      ),
                    ),
                    if (widget.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.labelSmall,
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                widget.icon == Icons.unfold_less_rounded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                size: 18,
                color: AppColors.doctorBlue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DoctorServiceTile extends StatefulWidget {
  const _DoctorServiceTile({
    required this.service,
    required this.onTap,
    this.mobileColumn = false,
  });

  final DoctorHomeServiceItem service;
  final VoidCallback onTap;
  final bool mobileColumn;

  @override
  State<_DoctorServiceTile> createState() => _DoctorServiceTileState();
}

class _DoctorServiceTileState extends State<_DoctorServiceTile> {
  bool _pressed = false;

  String get _label {
    if (widget.mobileColumn) {
      return widget.service.shortLabel ?? widget.service.label;
    }
    if (ResponsiveLayout.isExpanded(context)) return widget.service.label;
    return widget.service.shortLabel ?? widget.service.label;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mobileColumn) {
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
                  ? widget.service.gradient.first.withValues(alpha: 0.06)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ServiceIconBox(
                    service: widget.service, size: 44, iconSize: 20),
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
                ? widget.service.gradient.first.withValues(alpha: 0.06)
                : AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _pressed
                  ? widget.service.gradient.first.withValues(alpha: 0.35)
                  : AppColors.borderOf(context),
            ),
          ),
          child: Row(
            children: [
              _ServiceIconBox(service: widget.service, size: 46, iconSize: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                      widget.service.subtitle,
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
}

class _ServiceIconBox extends StatelessWidget {
  const _ServiceIconBox({
    required this.service,
    required this.size,
    required this.iconSize,
  });

  final DoctorHomeServiceItem service;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    if (service.assetPath != null) {
      return SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          service.assetPath!,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: service.gradient,
              ),
              borderRadius: BorderRadius.circular(13),
              boxShadow: [
                BoxShadow(
                  color: service.gradient.last.withValues(alpha: 0.24),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(service.icon, size: iconSize, color: Colors.white),
          ),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: service.gradient,
        ),
        borderRadius: BorderRadius.circular(13),
        boxShadow: [
          BoxShadow(
            color: service.gradient.last.withValues(alpha: 0.24),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(service.icon, size: iconSize, color: Colors.white),
    );
  }
}

class DoctorHomeSectionHeader extends StatelessWidget {
  const DoctorHomeSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.actionFilled = false,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.secondaryActionSubtitle,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool actionFilled;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final String? secondaryActionSubtitle;

  @override
  Widget build(BuildContext context) {
    final compact = ResponsiveLayout.isCompact(context);
    final hasSecondary =
        secondaryActionLabel != null && onSecondaryAction != null;
    final hasPrimary = actionLabel != null && onAction != null;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          compact ? 16 : 20, compact ? 14 : 18, compact ? 16 : 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: compact ? 15 : 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.bodySmall,
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (hasSecondary || hasPrimary) ...[
            const SizedBox(width: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (hasSecondary)
                  Material(
                    color: AppColors.doctorBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: onSecondaryAction,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    AppColors.doctorBlue,
                                    Color(0xFF0F4A82)
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(9),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.doctorBlue
                                        .withValues(alpha: 0.28),
                                    blurRadius: 6,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.calendar_month_rounded,
                                size: 18,
                                color: AppColors.surfaceOf(context),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  secondaryActionLabel!,
                                  style: GoogleFonts.inter(
                                    fontSize: AppTypography.labelMedium,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.doctorBlue,
                                    height: 1.1,
                                  ),
                                ),
                                if (secondaryActionSubtitle != null) ...[
                                  const SizedBox(height: 1),
                                  Text(
                                    secondaryActionSubtitle!,
                                    style: GoogleFonts.inter(
                                      fontSize: AppTypography.labelSmall,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondaryOf(context),
                                      height: 1.1,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (hasSecondary && hasPrimary) const SizedBox(width: 6),
                if (hasPrimary)
                  actionFilled
                      ? FilledButton(
                          onPressed: onAction,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.doctorBlue,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            textStyle: GoogleFonts.inter(
                              fontSize: AppTypography.bodySmall,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          child: Text(actionLabel!),
                        )
                      : TextButton(
                          onPressed: onAction,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.doctorBlue,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            minimumSize: const Size(0, 36),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(
                            actionLabel!,
                            style: GoogleFonts.inter(
                                fontSize: AppTypography.bodySmall,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class ClinicalToolsDrawer extends StatelessWidget {
  const ClinicalToolsDrawer({
    super.key,
    required this.title,
    required this.services,
  });

  final String title;
  final List<DoctorHomeServiceItem> services;

  static void show(
    BuildContext context, {
    required String title,
    required List<DoctorHomeServiceItem> services,
  }) {
    final compact = ResponsiveLayout.isCompact(context);

    if (compact) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) =>
            _ClinicalToolsBottomSheet(title: title, services: services),
      );
    } else {
      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Dismiss',
        barrierColor: Colors.black.withValues(alpha: 0.5),
        transitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (ctx, anim1, anim2) => Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: _ClinicalToolsSideDrawer(title: title, services: services),
          ),
        ),
        transitionBuilder: (ctx, anim, secondaryAnim, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
            child: child,
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class _ClinicalToolsSideDrawer extends StatelessWidget {
  const _ClinicalToolsSideDrawer({
    required this.title,
    required this.services,
  });

  final String title;
  final List<DoctorHomeServiceItem> services;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 440,
      height: MediaQuery.of(context).size.height,
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(-4, 0),
          ),
        ],
        border: Border(
          left: BorderSide(color: AppColors.borderOf(context)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 20, 20),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.borderOf(context)),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.doctorBlue, Color(0xFF2563EB)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.grid_view_rounded,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              title,
                              style: GoogleFonts.inter(
                                fontSize: AppTypography.headlineSmall,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimaryOf(context),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.doctorBlue
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '${services.length} tools',
                                style: GoogleFonts.inter(
                                  fontSize: AppTypography.labelSmall,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.doctorBlue,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Select a clinical management feature',
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.labelMedium,
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                    style: IconButton.styleFrom(
                      foregroundColor: AppColors.textSecondaryOf(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: services.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final s = services[index];
                return _DrawerToolTile(
                  service: s,
                  onTap: () {
                    Navigator.pop(context);
                    s.onTap();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ClinicalToolsBottomSheet extends StatelessWidget {
  const _ClinicalToolsBottomSheet({
    required this.title,
    required this.services,
  });

  final String title;
  final List<DoctorHomeServiceItem> services;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
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
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.borderOf(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.doctorBlue, Color(0xFF2563EB)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.grid_view_rounded,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: AppTypography.headlineSmall,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimaryOf(context),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.doctorBlue.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${services.length} tools',
                              style: GoogleFonts.inter(
                                fontSize: AppTypography.labelSmall,
                                fontWeight: FontWeight.w700,
                                color: AppColors.doctorBlue,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Select a tool to open',
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.labelMedium,
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.borderOf(context)),
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: services.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final s = services[index];
                return _DrawerToolTile(
                  service: s,
                  onTap: () {
                    Navigator.pop(context);
                    s.onTap();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerToolTile extends StatefulWidget {
  const _DrawerToolTile({
    required this.service,
    required this.onTap,
  });

  final DoctorHomeServiceItem service;
  final VoidCallback onTap;

  @override
  State<_DrawerToolTile> createState() => _DrawerToolTileState();
}

class _DrawerToolTileState extends State<_DrawerToolTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        onHover: (h) => setState(() => _hovered = h),
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: _hovered
                ? widget.service.gradient.first.withValues(alpha: 0.08)
                : AppColors.cardBgOf(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hovered
                  ? widget.service.gradient.first.withValues(alpha: 0.4)
                  : AppColors.borderOf(context),
              width: 1.2,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color:
                          widget.service.gradient.first.withValues(alpha: 0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    )
                  ]
                : [],
          ),
          child: Row(
            children: [
              _ServiceIconBox(service: widget.service, size: 48, iconSize: 24),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.service.label,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodyMedium,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    if (widget.service.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        widget.service.subtitle,
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.labelMedium,
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: widget.service.gradient.first,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
