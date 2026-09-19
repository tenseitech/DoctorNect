import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

double patientDoctorProfileMaxWidth(BuildContext context) =>
    ResponsiveLayout.contentMaxWidth(context).clamp(0.0, 640.0);

List<String> cleanProfileLabels(List<String> items) =>
    items.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

class PatientDoctorContentCard extends StatelessWidget {
  const PatientDoctorContentCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: child,
    );
  }
}

class PatientDoctorSectionTitle extends StatelessWidget {
  const PatientDoctorSectionTitle(this.text, {super.key, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: AppTypography.bodyLarge,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimaryOf(context),
          letterSpacing: -0.1,
        ),
      ),
    );
  }
}

class PatientDoctorTagWrap extends StatelessWidget {
  const PatientDoctorTagWrap({super.key, required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final labels = cleanProfileLabels(items);
    if (labels.isEmpty) {
      return Text(
        'Not added yet',
        style: GoogleFonts.inter(
            fontSize: AppTypography.bodyMedium,
            color: AppColors.textSecondaryOf(context)),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: labels.map((label) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.cardBgOf(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: AppTypography.bodySmall,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimaryOf(context),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class PatientDoctorMetaRow extends StatelessWidget {
  const PatientDoctorMetaRow({
    super.key,
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: AppColors.textSecondaryOf(context)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
                fontSize: AppTypography.bodyMedium,
                color: AppColors.textSecondaryOf(context),
                height: 1.4),
          ),
        ),
      ],
    );
  }
}

class PatientDoctorBulletItem extends StatelessWidget {
  const PatientDoctorBulletItem(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: Icon(Icons.circle,
                size: 5, color: AppColors.textSecondaryOf(context)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: GoogleFonts.inter(
                    fontSize: AppTypography.bodyMedium, height: 1.45)),
          ),
        ],
      ),
    );
  }
}

class PatientDoctorTimelineTile extends StatelessWidget {
  const PatientDoctorTimelineTile({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 6),
            decoration: const BoxDecoration(
              color: AppColors.patientTeal,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      fontSize: AppTypography.bodyMedium),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                      fontSize: AppTypography.bodySmall,
                      color: AppColors.textSecondaryOf(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Flat tab content — no nested card wrapper.
Widget patientDoctorTabList(
  BuildContext context, {
  required String pageKey,
  required List<Widget> children,
  EdgeInsets? padding,
  bool scrollable = true,
}) {
  final isCompact = MediaQuery.sizeOf(context).width < 600;
  final double h = isCompact ? 16 : 20;
  final double bottom = 100;

  final content = Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: children,
  );

  if (!scrollable) {
    return Padding(
      key: PageStorageKey<String>(pageKey),
      padding: padding ?? EdgeInsets.fromLTRB(h, 12, h, bottom),
      child: content,
    );
  }

  return ListView(
    key: PageStorageKey<String>(pageKey),
    primary: false,
    padding: padding ?? EdgeInsets.fromLTRB(h, 20, h, bottom),
    children: [content],
  );
}

/// Segmented tab bar container used in profile screen.
class PatientDoctorSegmentedTabBar extends StatelessWidget {
  const PatientDoctorSegmentedTabBar({super.key, required this.tabBar});

  final TabBar tabBar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: tabBar,
      ),
    );
  }
}
