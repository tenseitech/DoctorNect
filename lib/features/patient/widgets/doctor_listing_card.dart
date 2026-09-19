import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/layout/responsive_layout.dart';
import '../../../core/theme/app_colors.dart';
import 'package:medibond/features/patient/models/patient_models.dart';
import '../utils/doctor_display_name.dart';
import '../../../core/theme/app_typography.dart';

const _textGrey = Color(0xFF9CA3AF);
const _starColor = Color(0xFFF59E0B);

class DoctorListingCard extends StatelessWidget {
  const DoctorListingCard({
    super.key,
    required this.doctor,
    this.onBook,
    this.onViewProfile,
    this.onAddToMyDoctors,
    this.isInMyDoctors = false,
    this.grouped = false,
    this.flat = false,
    this.showDivider = false,
  });

  final DoctorListing doctor;
  final VoidCallback? onBook;
  final VoidCallback? onViewProfile;
  final VoidCallback? onAddToMyDoctors;
  final bool isInMyDoctors;
  final bool grouped;
  final bool flat;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final isWide = !ResponsiveLayout.isCompact(context);
    final body = isWide && flat ? _buildWideRow() : _buildCompactColumn();

    if (flat) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          body,
          if (showDivider)
            Divider(
                height: 1, thickness: 1, color: AppColors.borderOf(context)),
        ],
      );
    }

    if (grouped) {
      return Padding(padding: const EdgeInsets.all(16), child: body);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: body,
    );
  }

  Widget _buildWideRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DoctorAvatar(doctor: doctor, radius: 28),
          const SizedBox(width: 16),
          Expanded(child: _DoctorMeta(doctor: doctor, compactMeta: false)),
          const SizedBox(width: 20),
          _ActionColumn(
            onBook: onBook,
            onViewProfile: onViewProfile,
            onAddToMyDoctors: onAddToMyDoctors,
            isInMyDoctors: isInMyDoctors,
          ),
        ],
      ),
    );
  }

  Widget _buildCompactColumn() {
    final padding = flat
        ? const EdgeInsets.symmetric(horizontal: 16, vertical: 14)
        : EdgeInsets.zero;

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DoctorAvatar(doctor: doctor, radius: 24),
              const SizedBox(width: 12),
              Expanded(child: _DoctorMeta(doctor: doctor, compactMeta: true)),
            ],
          ),
          const SizedBox(height: 12),
          _LocationRow(doctor: doctor),
          const SizedBox(height: 8),
          _AvailabilityRow(doctor: doctor),
          if (doctor.languages.isNotEmpty) ...[
            const SizedBox(height: 10),
            _LanguageRow(languages: doctor.languages),
          ],
          const SizedBox(height: 12),
          _ActionRow(
            onBook: onBook,
            onViewProfile: onViewProfile,
            onAddToMyDoctors: onAddToMyDoctors,
            isInMyDoctors: isInMyDoctors,
          ),
        ],
      ),
    );
  }
}

class _DoctorAvatar extends StatelessWidget {
  const _DoctorAvatar({required this.doctor, required this.radius});

  final DoctorListing doctor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initial = doctor.name.trim().isNotEmpty
        ? doctor.name.trim()[0].toUpperCase()
        : 'D';
    final hasPhoto =
        doctor.photoUrl != null && doctor.photoUrl!.trim().isNotEmpty;

    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.patientTeal.withValues(alpha: 0.12),
      backgroundImage: hasPhoto ? NetworkImage(doctor.photoUrl!.trim()) : null,
      child: !hasPhoto
          ? Text(
              initial,
              style: GoogleFonts.inter(
                fontSize: radius * 0.72,
                fontWeight: FontWeight.w700,
                color: AppColors.patientTeal,
              ),
            )
          : null,
    );
  }
}

class _DoctorMeta extends StatelessWidget {
  const _DoctorMeta({required this.doctor, required this.compactMeta});

  final DoctorListing doctor;
  final bool compactMeta;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          formatDoctorDisplayName(doctor.name),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            fontSize: compactMeta ? 15 : 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '${doctor.specialization} · ${doctor.qualification}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            fontSize: AppTypography.bodySmall,
            color: AppColors.textSecondaryOf(context),
            height: 1.3,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              formatExperienceYears(doctor.experienceYears),
              style: GoogleFonts.inter(
                fontSize: AppTypography.labelMedium,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.star_rounded, size: 14, color: _starColor),
            const SizedBox(width: 2),
            Text(
              doctor.rating.toStringAsFixed(1),
              style: GoogleFonts.inter(
                fontSize: AppTypography.labelMedium,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimaryOf(context),
              ),
            ),
            if (doctor.reviewCount > 0) ...[
              Text(
                ' (${doctor.reviewCount})',
                style: GoogleFonts.inter(
                  fontSize: AppTypography.labelSmall,
                  color: AppColors.textSecondaryOf(context),
                ),
              ),
            ],
          ],
        ),
        if (!compactMeta) ...[
          const SizedBox(height: 10),
          _LocationRow(doctor: doctor),
          const SizedBox(height: 6),
          _AvailabilityRow(doctor: doctor),
          if (doctor.languages.isNotEmpty) ...[
            const SizedBox(height: 10),
            _LanguageRow(languages: doctor.languages),
          ],
        ],
      ],
    );
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({required this.doctor});

  final DoctorListing doctor;

  @override
  Widget build(BuildContext context) {
    final location = doctor.locationLabel.isNotEmpty
        ? doctor.locationLabel
        : '${doctor.clinicName} · ${doctor.distanceKm} km';

    return Row(
      children: [
        Icon(Icons.location_on_outlined,
            size: 14, color: AppColors.textSecondaryOf(context)),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            location,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: AppTypography.labelMedium,
              color: AppColors.textSecondaryOf(context),
            ),
          ),
        ),
        if (doctor.verified)
          const Padding(
            padding: EdgeInsets.only(left: 6),
            child: Icon(Icons.verified, color: Color(0xFF16A34A), size: 16),
          ),
      ],
    );
  }
}

class _AvailabilityRow extends StatelessWidget {
  const _AvailabilityRow({required this.doctor});

  final DoctorListing doctor;

  @override
  Widget build(BuildContext context) {
    final availabilityColor = doctor.availability == DoctorAvailability.today
        ? const Color(0xFF16A34A)
        : doctor.availability == DoctorAvailability.tomorrow
            ? const Color(0xFFF59E0B)
            : AppColors.textSecondaryOf(context);

    return Row(
      children: [
        Icon(Icons.schedule_outlined, size: 14, color: availabilityColor),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            formatAvailabilityLabel(doctor.availability, doctor.nextSlot),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: AppTypography.labelMedium,
              color: AppColors.textSecondaryOf(context),
            ),
          ),
        ),
      ],
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({required this.languages});

  final List<String> languages;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: languages.map((l) => _LanguagePill(label: l)).toList(),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    this.onBook,
    this.onViewProfile,
    this.onAddToMyDoctors,
    this.isInMyDoctors = false,
  });

  final VoidCallback? onBook;
  final VoidCallback? onViewProfile;
  final VoidCallback? onAddToMyDoctors;
  final bool isInMyDoctors;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton(
          onPressed: onBook,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.patientTeal,
            foregroundColor: AppColors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            minimumSize: const Size(0, 40),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: GoogleFonts.inter(
                fontSize: AppTypography.bodySmall, fontWeight: FontWeight.w600),
          ),
          child: const Text('Book Appointment'),
        ),
        OutlinedButton(
          onPressed: onViewProfile,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.patientTeal,
            side: const BorderSide(color: AppColors.patientTeal),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            minimumSize: const Size(0, 40),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: GoogleFonts.inter(
                fontSize: AppTypography.bodySmall, fontWeight: FontWeight.w600),
          ),
          child: const Text('View Profile'),
        ),
        if (onAddToMyDoctors != null || isInMyDoctors)
          OutlinedButton(
            onPressed: isInMyDoctors ? null : onAddToMyDoctors,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.patientTeal,
              disabledForegroundColor: AppColors.textSecondaryOf(context),
              side: BorderSide(
                color: isInMyDoctors
                    ? AppColors.borderOf(context)
                    : AppColors.patientTeal,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              minimumSize: const Size(0, 40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              textStyle: GoogleFonts.inter(
                  fontSize: AppTypography.bodySmall,
                  fontWeight: FontWeight.w600),
            ),
            child: Text(isInMyDoctors ? 'Added' : 'Add to My Doctors'),
          ),
      ],
    );
  }
}

class _ActionColumn extends StatelessWidget {
  const _ActionColumn({
    this.onBook,
    this.onViewProfile,
    this.onAddToMyDoctors,
    this.isInMyDoctors = false,
  });

  final VoidCallback? onBook;
  final VoidCallback? onViewProfile;
  final VoidCallback? onAddToMyDoctors;
  final bool isInMyDoctors;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 148,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed: onBook,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.patientTeal,
              foregroundColor: AppColors.white,
              minimumSize: const Size(double.infinity, 42),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              textStyle: GoogleFonts.inter(
                  fontSize: AppTypography.bodySmall,
                  fontWeight: FontWeight.w600),
            ),
            child: const Text('Book'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: onViewProfile,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.patientTeal,
              side: const BorderSide(color: AppColors.patientTeal),
              minimumSize: const Size(double.infinity, 42),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              textStyle: GoogleFonts.inter(
                  fontSize: AppTypography.bodySmall,
                  fontWeight: FontWeight.w600),
            ),
            child: const Text('View Profile'),
          ),
          if (onAddToMyDoctors != null || isInMyDoctors) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: isInMyDoctors ? null : onAddToMyDoctors,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.patientTeal,
                disabledForegroundColor: AppColors.textSecondaryOf(context),
                side: BorderSide(
                  color: isInMyDoctors
                      ? AppColors.borderOf(context)
                      : AppColors.patientTeal,
                ),
                minimumSize: const Size(double.infinity, 42),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                textStyle: GoogleFonts.inter(
                    fontSize: AppTypography.bodySmall,
                    fontWeight: FontWeight.w600),
              ),
              child: Text(isInMyDoctors ? 'Added' : 'Add to My Doctors'),
            ),
          ],
        ],
      ),
    );
  }
}

class _LanguagePill extends StatelessWidget {
  const _LanguagePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: AppTypography.labelSmall,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondaryOf(context),
        ),
      ),
    );
  }
}
