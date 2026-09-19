import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/theme/app_colors.dart';
import '../models/patient_profile_models.dart';
import '../utils/patient_bmi_utils.dart';
import 'profile_web_action_card.dart';
import '../../../../core/theme/app_typography.dart';

class ProfileWebLayout extends StatelessWidget {
  const ProfileWebLayout({
    super.key,
    required this.profile,
    required this.family,
    required this.avatar,
    required this.onPickPhoto,
    required this.onEdit,
    required this.onManageFamily,
    required this.onAddFamily,
    required this.onFamilyMemberTap,
    required this.healthActions,
    required this.careActions,
    required this.settingsActions,
  });

  final PatientProfile profile;
  final List<FamilyProfileMember> family;
  final Widget avatar;
  final VoidCallback onPickPhoto;
  final VoidCallback onEdit;
  final VoidCallback onManageFamily;
  final VoidCallback onAddFamily;
  final ValueChanged<FamilyProfileMember> onFamilyMemberTap;
  final List<ProfileWebActionData> healthActions;
  final List<ProfileWebActionData> careActions;
  final List<ProfileWebActionData> settingsActions;

  @override
  Widget build(BuildContext context) {
    final maxWidth = ResponsiveLayout.contentMaxWidth(context);
    final canPop = Navigator.canPop(context);
    final stacked = ResponsiveLayout.screenWidth(context) < ResponsiveLayout.mediumMaxWidth;

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
                    child: _ProfileIdentityPanel(
                      profile: profile,
                      family: family,
                      avatar: avatar,
                      onPickPhoto: onPickPhoto,
                      onEdit: onEdit,
                      onManageFamily: onManageFamily,
                      onAddFamily: onAddFamily,
                      onFamilyMemberTap: onFamilyMemberTap,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ..._mainPanels(columns: 2),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 320,
                      child: _ProfileIdentityPanel(
                        profile: profile,
                        family: family,
                        avatar: avatar,
                        onPickPhoto: onPickPhoto,
                        onEdit: onEdit,
                        onManageFamily: onManageFamily,
                        onAddFamily: onAddFamily,
                        onFamilyMemberTap: onFamilyMemberTap,
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(child: Column(children: _mainPanels(columns: 3))),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _mainPanels({required int columns}) => [
        _WebSectionPanel(
          title: 'My Health',
          subtitle: 'Conditions, allergies & vaccines',
          child: _ActionGrid(actions: healthActions, minTileHeight: 118, columns: columns),
        ),
        const SizedBox(height: 20),
        _WebSectionPanel(
          title: 'Care',
          subtitle: 'Prescriptions & medical documents',
          child: _ActionGrid(
            actions: careActions,
            minTileHeight: 118,
            columns: columns > 1 ? 2 : 1,
          ),
        ),
        const SizedBox(height: 20),
        _WebSectionPanel(
          title: 'Settings',
          subtitle: 'Notifications, security & support',
          child: _ActionGrid(
            actions: settingsActions,
            minTileHeight: 118,
            columns: 2,
          ),
        ),
      ];
}

class ProfileWebActionData {
  const ProfileWebActionData({
    required this.icon,
    required this.label,
    this.subtitle,
    this.onTap,
    this.iconGradient,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback? onTap;
  final List<Color>? iconGradient;
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
                'Manage your account, family & health records',
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

class _ProfileIdentityPanel extends StatelessWidget {
  const _ProfileIdentityPanel({
    required this.profile,
    required this.family,
    required this.avatar,
    required this.onPickPhoto,
    required this.onEdit,
    required this.onManageFamily,
    required this.onAddFamily,
    required this.onFamilyMemberTap,
  });

  final PatientProfile profile;
  final List<FamilyProfileMember> family;
  final Widget avatar;
  final VoidCallback onPickPhoto;
  final VoidCallback onEdit;
  final VoidCallback onManageFamily;
  final VoidCallback onAddFamily;
  final ValueChanged<FamilyProfileMember> onFamilyMemberTap;

  @override
  Widget build(BuildContext context) {
    final hasStats = profile.height > 0 && profile.weight > 0;
    final bmi = hasStats
        ? PatientBmiUtils.calculate(heightCm: profile.height, weightKg: profile.weight)
        : null;

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
            Center(
              child: GestureDetector(onTap: onPickPhoto, child: avatar),
            ),
            const SizedBox(height: 16),
            Text(
              profile.name.isNotEmpty ? profile.name : 'Your profile',
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
            if (profile.age > 0 || profile.gender.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (profile.age > 0) _MetaChip('${profile.age} yrs'),
                  if (profile.gender.trim().isNotEmpty) _MetaChip(profile.gender),
                ],
              ),
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
            if (hasStats && bmi != null) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _StatTile(
                      label: 'BMI',
                      value: bmi.toStringAsFixed(1),
                      highlight: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatTile(
                      label: 'Height',
                      value: '${profile.height.toStringAsFixed(0)} cm',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatTile(
                      label: 'Weight',
                      value: '${profile.weight.toStringAsFixed(0)} kg',
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(
                'Edit Profile',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.patientTeal,
                foregroundColor: AppColors.white,
                minimumSize: Size(double.infinity, 46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            SizedBox(height: 22),
            Divider(height: 1, color: AppColors.borderOf(context)),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Family',
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.bodyLarge,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimaryOf(context),
                        ),
                      ),
                      if (family.isNotEmpty)
                        Text(
                          '${family.length} member${family.length == 1 ? '' : 's'}',
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.labelMedium,
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: onManageFamily,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.patientTeal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Manage',
                    style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _WebFamilyList(
              family: family,
              onAddFamily: onAddFamily,
              onFamilyMemberTap: onFamilyMemberTap,
            ),
          ],
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

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({
    required this.actions,
    required this.minTileHeight,
    this.columns = 3,
  });

  final List<ProfileWebActionData> actions;
  final double minTileHeight;
  final int columns;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = columns.clamp(1, 4);
        final gap = 12.0;
        final tileWidth = (constraints.maxWidth - gap * (count - 1)) / count;

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
            ? AppColors.patientTeal.withValues(alpha: 0.08)
            : AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight
              ? AppColors.patientTeal.withValues(alpha: 0.2)
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
              color: highlight ? AppColors.patientTeal : AppColors.textPrimaryOf(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _WebFamilyList extends StatelessWidget {
  const _WebFamilyList({
    required this.family,
    required this.onAddFamily,
    required this.onFamilyMemberTap,
  });

  final List<FamilyProfileMember> family;
  final VoidCallback onAddFamily;
  final ValueChanged<FamilyProfileMember> onFamilyMemberTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (family.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Text(
                'No family profiles yet',
                style: GoogleFonts.inter(
                  fontSize: AppTypography.bodySmall,
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
            )
          else
            for (var i = 0; i < family.length; i++) ...[
              _WebFamilyRow(
                member: family[i],
                onTap: () => onFamilyMemberTap(family[i]),
              ),
              if (i < family.length - 1)
                Divider(height: 1, thickness: 1, indent: 58, color: AppColors.borderOf(context)),
            ],
          Divider(height: 1, thickness: 1, color: AppColors.borderOf(context)),
          _WebAddFamilyRow(onTap: onAddFamily),
        ],
      ),
    );
  }
}

class _WebFamilyRow extends StatelessWidget {
  const _WebFamilyRow({required this.member, required this.onTap});

  final FamilyProfileMember member;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final initial =
        (member.photoInitial ?? (member.name.isNotEmpty ? member.name[0] : 'F')).toUpperCase();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                child: Text(
                  initial,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.bodySmall,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF7C3AED),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodyMedium,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      member.relationLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
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
    );
  }
}

class _WebAddFamilyRow extends StatelessWidget {
  const _WebAddFamilyRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.patientTeal.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.add_rounded, color: AppColors.patientTeal, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Add family member',
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.bodyMedium,
                    fontWeight: FontWeight.w600,
                    color: AppColors.patientTeal,
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
