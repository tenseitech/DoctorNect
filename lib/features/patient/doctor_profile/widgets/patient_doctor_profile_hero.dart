import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/session/doctor_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../appointments/models/patient_appointment_models.dart';
import '../models/doctor_profile_detail.dart';
import 'patient_doctor_profile_shared.dart';
import '../../../../core/theme/app_typography.dart';

class PatientDoctorProfileHero extends StatelessWidget {
  const PatientDoctorProfileHero({
    super.key,
    required this.doctor,
    required this.avatar,
    this.reviewableVisit,
    this.onRateDoctor,
    this.onBook,
    this.onCall,
    this.onShare,
  });

  final DoctorProfileDetail doctor;
  final Widget avatar;
  final PatientAppointment? reviewableVisit;
  final VoidCallback? onRateDoctor;
  final VoidCallback? onBook;
  final VoidCallback? onCall;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    final isPatientView = DoctorSession.loggedInDoctorId.isEmpty;
    final compact = ResponsiveLayout.isCompact(context);
    final double h = compact ? 16.0 : 20.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(h, 8, h, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HeroHeaderCard(
            doctor: doctor,
            avatar: avatar,
            onCall: onCall,
            onShare: onShare,
          ),
          const SizedBox(height: 14),
          _DoctorStatsStrip(doctor: doctor),
          if (doctor.languages.isNotEmpty || doctor.area.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            _MetaStrip(doctor: doctor),
          ],
          if (isPatientView && onBook != null && !compact) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onBook,
              icon: const Icon(Icons.calendar_month_rounded, size: 20),
              label: const Text('Book Appointment'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.patientTeal,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: GoogleFonts.inter(fontSize: AppTypography.bodyLarge, fontWeight: FontWeight.w600),
              ),
            ),
          ],
          if (isPatientView && reviewableVisit != null && onRateDoctor != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onRateDoctor,
              icon: const Icon(Icons.star_outline_rounded, size: 18),
              label: const Text('Rate your last visit'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.patientTeal,
                side: const BorderSide(color: AppColors.patientTeal),
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: GoogleFonts.inter(fontSize: AppTypography.bodyMedium, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroHeaderCard extends StatelessWidget {
  const _HeroHeaderCard({
    required this.doctor,
    required this.avatar,
    this.onCall,
    this.onShare,
  });

  final DoctorProfileDetail doctor;
  final Widget avatar;
  final VoidCallback? onCall;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderOf(context)),
        boxShadow: [
          BoxShadow(
            color: AppColors.patientTeal.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 52),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.patientTeal.withValues(alpha: 0.14),
                  AppColors.patientTeal.withValues(alpha: 0.04),
                ],
              ),
            ),
            child: Row(
              children: [
                if (onCall != null)
                  _QuickAction(
                    icon: Icons.phone_rounded,
                    label: 'Call',
                    onTap: onCall!,
                  ),
                const Spacer(),
                if (onShare != null)
                  _QuickAction(
                    icon: Icons.ios_share_rounded,
                    label: 'Share',
                    onTap: onShare!,
                  ),
              ],
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -36),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.surfaceOf(context),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: avatar,
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _DoctorIdentity(doctor: doctor),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceOf(context).withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: AppColors.patientTeal),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: AppTypography.bodySmall,
                  fontWeight: FontWeight.w600,
                  color: AppColors.patientTeal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DoctorIdentity extends StatelessWidget {
  const _DoctorIdentity({required this.doctor});

  final DoctorProfileDetail doctor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                'Dr. ${doctor.name}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: AppTypography.headlineLarge,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimaryOf(context),
                  height: 1.2,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            if (doctor.verified) ...[
              const SizedBox(width: 6),
              const Icon(Icons.verified_rounded, color: Color(0xFF16A34A), size: 22),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          doctor.specialization,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: AppTypography.bodyMedium,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondaryOf(context),
          ),
        ),
        if (doctor.qualification.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            doctor.qualification,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, color: AppColors.textSecondaryOf(context)),
          ),
        ],
      ],
    );
  }
}

class _MetaStrip extends StatelessWidget {
  const _MetaStrip({required this.doctor});

  final DoctorProfileDetail doctor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        children: [
          if (doctor.area.trim().isNotEmpty)
            PatientDoctorMetaRow(icon: Icons.location_on_outlined, text: doctor.area),
          if (doctor.languages.isNotEmpty) ...[
            if (doctor.area.trim().isNotEmpty) const SizedBox(height: 8),
            PatientDoctorMetaRow(
              icon: Icons.translate_rounded,
              text: doctor.languages.join(', '),
            ),
          ],
        ],
      ),
    );
  }
}

class _DoctorStatsStrip extends StatelessWidget {
  const _DoctorStatsStrip({required this.doctor});

  final DoctorProfileDetail doctor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatCell(
              label: 'Rating',
              value: doctor.rating.toStringAsFixed(1),
              icon: Icons.star_rounded,
              iconColor: const Color(0xFFF59E0B),
              subtitle: '${doctor.reviewCount} reviews',
            ),
          ),
          Container(width: 1, height: 40, color: AppColors.borderOf(context)),
          Expanded(
            child: _StatCell(
              label: 'Experience',
              value: '${doctor.experienceYears}',
              subtitle: 'years',
            ),
          ),
          Container(width: 1, height: 40, color: AppColors.borderOf(context)),
          Expanded(
            child: _StatCell(
              label: 'Patients',
              value: doctor.reviewCount > 0 ? '${doctor.reviewCount}+' : '—',
              subtitle: 'reviewed',
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.label,
    required this.value,
    this.subtitle,
    this.icon,
    this.iconColor,
  });

  final String label;
  final String value;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(fontSize: AppTypography.labelSmall, color: AppColors.textSecondaryOf(context)),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: iconColor),
                const SizedBox(width: 3),
              ],
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.headlineSmall,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 10, color: AppColors.textSecondaryOf(context)),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class PatientDoctorProfileBottomBar extends StatelessWidget {
  const PatientDoctorProfileBottomBar({
    super.key,
    required this.onBook,
    this.secondaryLabel,
    this.onSecondary,
  });

  final VoidCallback onBook;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          border: Border(top: BorderSide(color: AppColors.borderOf(context))),
          boxShadow: [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 12,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: 1.0,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: patientDoctorProfileMaxWidth(context)),
            child: Row(
              children: [
                if (secondaryLabel != null && onSecondary != null) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onSecondary,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.patientTeal,
                        side: const BorderSide(color: AppColors.patientTeal),
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        textStyle: GoogleFonts.inter(fontSize: AppTypography.bodyMedium, fontWeight: FontWeight.w600),
                      ),
                      child: Text(
                        secondaryLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  flex: secondaryLabel != null ? 2 : 1,
                  child: FilledButton.icon(
                    onPressed: onBook,
                    icon: const Icon(Icons.calendar_month_rounded, size: 20),
                    label: const Text('Book Appointment'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.patientTeal,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: GoogleFonts.inter(fontSize: AppTypography.bodyLarge, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
