import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/theme/app_colors.dart';
import '../../widgets/doctor_ui_widgets.dart';
import 'package:medibond/features/patient/models/patient_models.dart';
import '../../../../core/theme/app_typography.dart';

class PatientListCard extends StatelessWidget {
  const PatientListCard({
    super.key,
    required this.patient,
    required this.onViewProfile,
  });

  final DoctorPatientSummary patient;
  final VoidCallback onViewProfile;

  @override
  Widget build(BuildContext context) {
    final wide = !ResponsiveLayout.isCompact(context);

    return Material(
      color: AppColors.surfaceOf(context),
      borderRadius: BorderRadius.circular(AppConstants.cardRadius),
      child: InkWell(
        onTap: onViewProfile,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: EdgeInsets.all(wide ? 16 : 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.cardRadius),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: wide ? _buildWideLayout(context) : _buildCompactLayout(context),
        ),
      ),
    );
  }

  Widget _buildCompactLayout(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PatientHeader(patient: patient),
        if (patient.conditions.isNotEmpty) ...[
          const SizedBox(height: 10),
          _ConditionChips(conditions: patient.conditions),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: _ViewProfileButton(onPressed: onViewProfile),
        ),
      ],
    );
  }

  Widget _buildWideLayout(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        PatientAvatar(name: patient.name, gender: patient.gender),
        const SizedBox(width: 16),
        Expanded(child: _PatientDetails(patient: patient, showTypeBadge: true)),
        if (patient.conditions.isNotEmpty) ...[
          const SizedBox(width: 12),
          SizedBox(
            width: 160,
            child: _ConditionChips(conditions: patient.conditions, maxVisible: 2),
          ),
        ],
        const SizedBox(width: 16),
        Container(
          width: 1,
          height: 56,
          color: AppColors.borderOf(context),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            _VisitsBadge(count: patient.totalVisits),
            const SizedBox(height: 10),
            _ViewProfileButton(onPressed: onViewProfile),
          ],
        ),
      ],
    );
  }
}

class _PatientHeader extends StatelessWidget {
  const _PatientHeader({required this.patient});

  final DoctorPatientSummary patient;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PatientAvatar(name: patient.name, gender: patient.gender),
        const SizedBox(width: 12),
        Expanded(child: _PatientDetails(patient: patient, showTypeBadge: true)),
        _VisitsBadge(count: patient.totalVisits),
      ],
    );
  }
}

class _PatientDetails extends StatelessWidget {
  const _PatientDetails({
    required this.patient,
    this.showTypeBadge = false,
  });

  final DoctorPatientSummary patient;
  final bool showTypeBadge;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                patient.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: AppTypography.bodyLarge,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimaryOf(context),
                ),
              ),
            ),
            if (showTypeBadge && patient.isNew)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: StatusBadge(label: 'New', color: AppColors.doctorBlue),
              )
            else if (showTypeBadge && patient.isFollowUp)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: StatusBadge(label: 'Follow-up', color: const Color(0xFF7C3AED)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${patient.age} yrs · ${AppConstants.patientGenderLabel(patient.gender)} · ${patient.mobile}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context)),
        ),
        const SizedBox(height: 4),
        Text(
          'Last visit: ${DateFormat('dd MMM yyyy').format(patient.lastVisitDate)}',
          style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context)),
        ),
      ],
    );
  }
}

class _VisitsBadge extends StatelessWidget {
  const _VisitsBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.doctorBlue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count visits',
        style: GoogleFonts.inter(
          fontSize: AppTypography.labelSmall,
          fontWeight: FontWeight.w600,
          color: AppColors.doctorBlue,
        ),
      ),
    );
  }
}

class _ConditionChips extends StatelessWidget {
  const _ConditionChips({
    required this.conditions,
    this.maxVisible,
  });

  final List<String> conditions;
  final int? maxVisible;

  @override
  Widget build(BuildContext context) {
    final visible = maxVisible == null ? conditions : conditions.take(maxVisible!).toList();
    final hidden = maxVisible == null ? 0 : conditions.length - visible.length;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.start,
      children: [
        for (final c in visible)
          StatusBadge(label: c, color: const Color(0xFF7C3AED)),
        if (hidden > 0)
          Text(
            '+$hidden more',
            style: GoogleFonts.inter(fontSize: AppTypography.labelSmall, color: AppColors.textSecondaryOf(context)),
          ),
      ],
    );
  }
}

class _ViewProfileButton extends StatelessWidget {
  const _ViewProfileButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.doctorBlue,
          side: const BorderSide(color: AppColors.doctorBlue),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Text(
          'View Profile',
          style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
