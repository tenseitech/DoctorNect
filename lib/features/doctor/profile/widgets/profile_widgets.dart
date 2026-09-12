import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../widgets/profile_photo_avatar.dart';
import '../../widgets/doctor_ui_widgets.dart';
import '../../models/doctor_models.dart';

void showProfileSavedToast(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Profile saved successfully', style: GoogleFonts.inter()),
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF16A34A),
    ),
  );
}

class ProfileSectionHeader extends StatelessWidget {
  const ProfileSectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondaryOf(context),
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class ProfileSettingsItem {
  const ProfileSettingsItem({
    required this.title,
    required this.icon,
    required this.onTap,
    this.subtitle,
    this.iconColor,
    this.iconBackground,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final Color? iconColor;
  final Color? iconBackground;
}

class ProfileSettingsGroup extends StatelessWidget {
  const ProfileSettingsGroup({super.key, required this.items});

  final List<ProfileSettingsItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderOf(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 68, endIndent: 16),
            _ProfileSettingsRow(item: items[i]),
          ],
        ],
      ),
    );
  }
}

class _ProfileSettingsRow extends StatelessWidget {
  const _ProfileSettingsRow({required this.item});

  final ProfileSettingsItem item;

  @override
  Widget build(BuildContext context) {
    final iconColor = item.iconColor ?? AppColors.doctorBlue;
    final iconBg = item.iconBackground ?? iconColor.withValues(alpha: 0.1);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(item.icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    if (item.subtitle != null && item.subtitle!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.subtitle!,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.textSecondaryOf(context),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: AppColors.textSecondaryOf(context).withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Legacy tile — kept for any external references.
class ProfileSectionTile extends StatelessWidget {
  const ProfileSectionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ProfileSettingsGroup(
      items: [
        ProfileSettingsItem(
          title: title,
          subtitle: subtitle,
          icon: icon,
          onTap: onTap,
        ),
      ],
    );
  }
}

class ProfileHeroHeader extends StatelessWidget {
  const ProfileHeroHeader({
    super.key,
    required this.displayName,
    required this.specialization,
    required this.verificationStatus,
    required this.rating,
    required this.reviewCount,
    this.photoPath,
    this.photoBytes,
    this.photoUrl,
    required this.onEditPhoto,
    required this.onEditProfile,
  });

  final String displayName;
  final String specialization;
  final VerificationStatus verificationStatus;
  final double rating;
  final int reviewCount;
  final String? photoPath;
  final Uint8List? photoBytes;
  final String? photoUrl;
  final VoidCallback onEditPhoto;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderOf(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            height: 4,
            color: AppColors.doctorBlue.withValues(alpha: 0.85),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.doctorBlue.withValues(alpha: 0.2),
                          width: 2,
                        ),
                      ),
                      child: ProfilePhotoAvatar(
                        displayName: displayName,
                        photoPath: photoPath,
                        photoBytes: photoBytes,
                        photoUrl: photoUrl,
                        radius: 42,
                      ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Material(
                        color: AppColors.doctorBlue,
                        shape: const CircleBorder(),
                        elevation: 1,
                        child: InkWell(
                          onTap: onEditPhoto,
                          customBorder: CircleBorder(),
                          child: Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(
                              Icons.camera_alt_rounded,
                              size: 14,
                              color: AppColors.surfaceOf(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  displayName,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimaryOf(context),
                    height: 1.2,
                  ),
                ),
                if (specialization.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    specialization.trim(),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                VerificationBadge(status: verificationStatus),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _HeroStatChip(
                        icon: Icons.star_rounded,
                        label: rating > 0 ? rating.toStringAsFixed(1) : '—',
                        caption: 'Rating',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _HeroStatChip(
                        icon: Icons.rate_review_outlined,
                        label: '$reviewCount',
                        caption: 'Reviews',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onEditProfile,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(
                      'Edit Profile',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.doctorBlue,
                      side: BorderSide(color: AppColors.doctorBlue.withValues(alpha: 0.45)),
                      minimumSize: const Size(double.infinity, 44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
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

class _HeroStatChip extends StatelessWidget {
  const _HeroStatChip({
    required this.icon,
    required this.label,
    required this.caption,
  });

  final IconData icon;
  final String label;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFFF59E0B)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimaryOf(context),
                    height: 1.1,
                  ),
                ),
                Text(
                  caption,
                  style: GoogleFonts.inter(
                    fontSize: 11,
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

/// Alias for backward compatibility.
typedef ProfileTopCard = ProfileHeroHeader;

class EditableSectionScaffold extends StatefulWidget {
  const EditableSectionScaffold({
    super.key,
    required this.title,
    required this.child,
    required this.onSave,
    required this.buildSnapshot,
  });

  final String title;
  final Widget child;
  final VoidCallback onSave;
  final String Function() buildSnapshot;

  @override
  State<EditableSectionScaffold> createState() => _EditableSectionScaffoldState();
}

class _EditableSectionScaffoldState extends State<EditableSectionScaffold> {
  late String _initialSnapshot;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _initialSnapshot = widget.buildSnapshot();
  }

  void markDirty() {
    final current = widget.buildSnapshot();
    final dirty = current != _initialSnapshot;
    if (dirty != _dirty) setState(() => _dirty = dirty);
  }

  void _save() {
    widget.onSave();
    _initialSnapshot = widget.buildSnapshot();
    setState(() => _dirty = false);
    showProfileSavedToast(context);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: AppBar(
        title: Text(
          widget.title,
          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
        backgroundColor: AppColors.surfaceOf(context),
        foregroundColor: AppColors.textPrimaryOf(context),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (_) {
                markDirty();
                return false;
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Builder(
                    builder: (context) {
                      WidgetsBinding.instance.addPostFrameCallback((_) => markDirty());
                      return widget.child;
                    },
                  ),
                ],
              ),
            ),
          ),
          if (_dirty)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceOf(context),
                      border: Border(top: BorderSide(color: AppColors.borderOf(context))),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 12,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: FilledButton(
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.doctorBlue,
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Save Changes',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700),
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
}
