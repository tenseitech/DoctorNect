import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import 'package:medibond/features/patient/models/patient_models.dart';
import '../../../../core/theme/app_typography.dart';

class HomeDoctorTile extends StatefulWidget {
  const HomeDoctorTile({
    super.key,
    required this.doctor,
    required this.onTap,
    required this.onBook,
    this.onRemove,
  });

  static const cardWidth = 142.0;
  static const cardHeight = 162.0;

  final MyDoc doctor;
  final VoidCallback onTap;
  final VoidCallback onBook;
  final VoidCallback? onRemove;

  @override
  State<HomeDoctorTile> createState() => _HomeDoctorTileState();
}

class _HomeDoctorTileState extends State<HomeDoctorTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final doctor = widget.doctor;
    final initial = doctor.name.isNotEmpty ? doctor.name[0].toUpperCase() : 'D';
    final hasPhoto =
        doctor.photoUrl != null && doctor.photoUrl!.trim().isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          InkWell(
            onTap: widget.onTap,
            onHighlightChanged: (value) => setState(() => _pressed = value),
            borderRadius: BorderRadius.circular(16),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: HomeDoctorTile.cardWidth,
              height: HomeDoctorTile.cardHeight,
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              decoration: BoxDecoration(
                color: _pressed
                    ? AppColors.patientTeal.withValues(alpha: 0.05)
                    : AppColors.cardBgOf(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _pressed
                      ? AppColors.patientTeal.withValues(alpha: 0.35)
                      : AppColors.borderOf(context),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.textPrimaryOf(context)
                        .withValues(alpha: _pressed ? 0.02 : 0.04),
                    blurRadius: _pressed ? 8 : 12,
                    offset: Offset(0, _pressed ? 2 : 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 46,
                      height: 46,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF0D9488), Color(0xFF0369A1)],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color:
                                AppColors.patientTeal.withValues(alpha: 0.24),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        backgroundColor: AppColors.surfaceOf(context),
                        backgroundImage: hasPhoto
                            ? NetworkImage(doctor.photoUrl!.trim())
                            : null,
                        child: hasPhoto
                            ? null
                            : Text(
                                initial,
                                style: GoogleFonts.inter(
                                  fontSize: AppTypography.headlineSmall,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.patientTeal,
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Dr. ${doctor.name}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.labelMedium,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimaryOf(context),
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    doctor.specialization,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: AppColors.textSecondaryOf(context),
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 12, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 2),
                        Text(
                          doctor.rating.toStringAsFixed(1),
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                        if (doctor.reviewCount > 0) ...[
                          Text(
                            ' · ${doctor.reviewCount}',
                            style: GoogleFonts.inter(
                              fontSize: 9.5,
                              color: AppColors.textSecondaryOf(context),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 28,
                    child: FilledButton(
                      onPressed: widget.onBook,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.patientTeal,
                        foregroundColor: AppColors.white,
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Book',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                            fontSize: 10.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (widget.onRemove != null)
            Positioned(
              top: -4,
              right: -4,
              child: Material(
                color: AppColors.surfaceOf(context),
                shape: const CircleBorder(),
                elevation: 2,
                shadowColor:
                    AppColors.textPrimaryOf(context).withValues(alpha: 0.15),
                child: InkWell(
                  onTap: widget.onRemove,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.borderOf(context)),
                    ),
                    child: Icon(
                      Icons.close,
                      size: 14,
                      color: AppColors.textSecondaryOf(context),
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

class HomeDoctorInlineMessage extends StatelessWidget {
  const HomeDoctorInlineMessage({
    super.key,
    required this.icon,
    required this.text,
    this.action,
  });

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.patientTeal
                  .withValues(alpha: isDark ? 0.14 : 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 22,
              color: AppColors.patientTeal,
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: AppTypography.bodySmall,
                color: AppColors.textSecondaryOf(context),
                height: 1.35,
              ),
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 14),
            action!,
          ],
        ],
      ),
    );
  }
}
