import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../patient/profile/widgets/profile_web_action_card.dart';
import '../../../patient/profile/widgets/profile_web_layout.dart';
import '../../models/doctor_models.dart';
import '../../widgets/doctor_ui_widgets.dart';
import '../models/doctor_profile_data.dart';
import '../../../../core/theme/app_typography.dart';

class DoctorProfileWebLayout extends StatelessWidget {
  const DoctorProfileWebLayout({
    super.key,
    required this.profile,
    required this.displayName,
    required this.verificationStatus,
    required this.avatar,
    required this.onPickPhoto,
    required this.onEdit,
    required this.profileActions,
    required this.accountActions,
    required this.networkActions,
    required this.insightsActions,
  });

  final DoctorProfileData profile;
  final String displayName;
  final VerificationStatus verificationStatus;
  final Widget avatar;
  final VoidCallback onPickPhoto;
  final VoidCallback onEdit;
  final List<ProfileWebActionData> profileActions;
  final List<ProfileWebActionData> accountActions;
  final List<ProfileWebActionData> networkActions;
  final List<ProfileWebActionData> insightsActions;

  List<ProfileWebActionData> get _sidebarQuickLinks => [
        ...accountActions,
        ...insightsActions,
      ];

  @override
  Widget build(BuildContext context) {
    final maxWidth = ResponsiveLayout.contentMaxWidth(context);
    final canPop = Navigator.canPop(context);
    final stacked = ResponsiveLayout.screenWidth(context) < ResponsiveLayout.mediumMaxWidth;

    final identityPanel = _DoctorIdentityPanel(
      profile: profile,
      displayName: displayName,
      verificationStatus: verificationStatus,
      avatar: avatar,
      onPickPhoto: onPickPhoto,
      onEdit: onEdit,
      quickLinks: _sidebarQuickLinks,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _WebPageHeader(canPop: canPop),
              const SizedBox(height: 24),
              if (stacked) ...[
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: identityPanel,
                  ),
                ),
                const SizedBox(height: 20),
                ..._mainPanels(compact: true),
              ]               else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 320,
                      child: identityPanel,
                    ),
                    const SizedBox(width: 24),
                    Expanded(child: Column(children: _mainPanels(compact: false))),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _mainPanels({required bool compact}) {
    final columns = compact ? 2 : 2;
    return [
      _WebSectionPanel(
        title: 'My Profile',
        subtitle: 'Personal, professional & clinic details',
        child: _AdaptiveActionLayout(
          actions: profileActions,
          preferredColumns: columns,
          minTileHeight: 118,
        ),
      ),
      const SizedBox(height: 20),
      _WebSectionPanel(
        title: 'Network & Services',
        subtitle: 'Pharmacy, labs & ambulance',
        child: _AdaptiveActionLayout(
          actions: networkActions,
          preferredColumns: compact ? 2 : 3,
          minTileHeight: 118,
        ),
      ),
      if (compact) ...[
        const SizedBox(height: 20),
        _WebSectionPanel(
          title: 'Account & Insights',
          subtitle: 'Security, reviews & analytics',
          child: _AdaptiveActionLayout(
            actions: _sidebarQuickLinks,
            preferredColumns: 2,
            minTileHeight: 96,
            preferRows: true,
          ),
        ),
      ],
    ];
  }
}

class _WebPageHeader extends StatelessWidget {
  const _WebPageHeader({required this.canPop});

  final bool canPop;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (canPop) ...[
          IconButton(
            onPressed: () => Navigator.maybePop(context),
            icon: Icon(Icons.arrow_back_rounded),
            style: IconButton.styleFrom(
              foregroundColor: AppColors.textPrimaryOf(context),
              backgroundColor: AppColors.surfaceOf(context),
              side: BorderSide(color: AppColors.borderOf(context)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(width: 14),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Profile',
                style: GoogleFonts.inter(
                  fontSize: AppTypography.headlineLarge,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimaryOf(context),
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Manage your practice, network & account',
                style: GoogleFonts.inter(
                  fontSize: AppTypography.bodyMedium,
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DoctorIdentityPanel extends StatelessWidget {
  const _DoctorIdentityPanel({
    required this.profile,
    required this.displayName,
    required this.verificationStatus,
    required this.avatar,
    required this.onPickPhoto,
    required this.onEdit,
    required this.quickLinks,
  });

  final DoctorProfileData profile;
  final String displayName;
  final VerificationStatus verificationStatus;
  final Widget avatar;
  final VoidCallback onPickPhoto;
  final VoidCallback onEdit;
  final List<ProfileWebActionData> quickLinks;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(child: GestureDetector(onTap: onPickPhoto, child: avatar)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    displayName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.headlineLarge,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimaryOf(context),
                      height: 1.15,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                VerificationBadge(status: verificationStatus),
              ],
            ),
            if (profile.specialization.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Center(child: _MetaChip(profile.specialization.trim())),
            ],
            if (profile.mobile.trim().isNotEmpty || profile.email.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              if (profile.mobile.trim().isNotEmpty)
                _ContactRow(icon: Icons.phone_outlined, text: profile.mobile),
              if (profile.email.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                _ContactRow(icon: Icons.mail_outline, text: profile.email),
              ],
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    label: 'Rating',
                    value: profile.rating > 0 ? profile.rating.toStringAsFixed(1) : '—',
                    highlight: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatTile(
                    label: 'Reviews',
                    value: '${profile.reviewCount}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(
                'Edit Profile',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.doctorBlue,
                foregroundColor: AppColors.white,
                minimumSize: Size(double.infinity, 46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            if (quickLinks.isNotEmpty) ...[
              SizedBox(height: 22),
              Divider(height: 1, color: AppColors.borderOf(context)),
              const SizedBox(height: 18),
              Text(
                'Quick access',
                style: GoogleFonts.inter(
                  fontSize: AppTypography.bodyMedium,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Account, reviews & reports',
                style: GoogleFonts.inter(
                  fontSize: AppTypography.labelMedium,
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.cardBgOf(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.borderOf(context)),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < quickLinks.length; i++) ...[
                      _SidebarQuickLink(action: quickLinks[i]),
                      if (i < quickLinks.length - 1)
                        Divider(height: 1, thickness: 1, indent: 58, color: AppColors.borderOf(context)),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SidebarQuickLink extends StatefulWidget {
  const _SidebarQuickLink({required this.action});

  final ProfileWebActionData action;

  @override
  State<_SidebarQuickLink> createState() => _SidebarQuickLinkState();
}

class _SidebarQuickLinkState extends State<_SidebarQuickLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final gradient = widget.action.iconGradient ?? const [AppColors.doctorBlue, Color(0xFF0F4A82)];

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: _hovered ? AppColors.surfaceOf(context) : Colors.transparent,
        child: InkWell(
          onTap: widget.action.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradient,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(widget.action.icon, size: 18, color: AppColors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.action.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.bodySmall,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimaryOf(context),
                        ),
                      ),
                      if (widget.action.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.action.subtitle!,
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
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.textSecondaryOf(context).withValues(alpha: 0.75),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WebSectionPanel extends StatelessWidget {
  const _WebSectionPanel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: AppTypography.headlineSmall,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, color: AppColors.textSecondaryOf(context)),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _AdaptiveActionLayout extends StatelessWidget {
  const _AdaptiveActionLayout({
    required this.actions,
    required this.preferredColumns,
    required this.minTileHeight,
    this.preferRows = false,
  });

  final List<ProfileWebActionData> actions;
  final int preferredColumns;
  final double minTileHeight;
  final bool preferRows;

  int _columnCount(double width) {
    if (actions.isEmpty) return 1;
    if (preferRows || actions.length == 1) return 1;
    if (actions.length == 3 && width >= 520) return 3;
    if (actions.length == 2) return 2;
    return preferredColumns.clamp(1, 4);
  }

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnCount(constraints.maxWidth);
        final gap = 12.0;

        if (columns == 1) {
          return Column(
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) SizedBox(height: gap),
                SizedBox(
                  height: 72,
                  child: _WebActionRowCard(action: actions[i]),
                ),
              ],
            ],
          );
        }

        final tileWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final action in actions)
              SizedBox(
                width: tileWidth,
                height: minTileHeight,
                child: ProfileWebActionCard(
                  icon: action.icon,
                  label: action.label,
                  subtitle: action.subtitle,
                  onTap: action.onTap,
                  iconGradient: action.iconGradient,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _WebActionRowCard extends StatefulWidget {
  const _WebActionRowCard({required this.action});

  final ProfileWebActionData action;

  @override
  State<_WebActionRowCard> createState() => _WebActionRowCardState();
}

class _WebActionRowCardState extends State<_WebActionRowCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final gradient = widget.action.iconGradient ?? const [AppColors.doctorBlue, Color(0xFF0F4A82)];

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: _hovered ? AppColors.cardBgOf(context) : AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: widget.action.onTap,
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _hovered
                    ? AppColors.doctorBlue.withValues(alpha: 0.35)
                    : AppColors.borderOf(context),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: gradient,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(widget.action.icon, size: 21, color: AppColors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.action.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.bodyMedium,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimaryOf(context),
                        ),
                      ),
                      if (widget.action.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.action.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: AppColors.textSecondaryOf(context).withValues(alpha: 0.8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(
          fontSize: AppTypography.labelMedium,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimaryOf(context),
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.textSecondaryOf(context)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, color: AppColors.textSecondaryOf(context)),
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.doctorBlue.withValues(alpha: 0.08)
            : AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight
              ? AppColors.doctorBlue.withValues(alpha: 0.2)
              : AppColors.borderOf(context),
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: AppTypography.labelSmall,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: AppTypography.bodyLarge,
              fontWeight: FontWeight.w800,
              color: highlight ? AppColors.doctorBlue : AppColors.textPrimaryOf(context),
            ),
          ),
        ],
      ),
    );
  }
}
