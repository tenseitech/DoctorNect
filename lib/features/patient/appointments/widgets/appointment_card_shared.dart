import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/registered_doctors_store.dart';

const _cardBorder = Color(0xFFE5E7EB);
const _textGray400 = Color(0xFF9CA3AF);
const _starColor = Color(0xFFF59E0B);

BoxDecoration appointmentTabCardDecoration([BuildContext? context]) {
  return BoxDecoration(
    color: context != null ? AppColors.surfaceOf(context) : Colors.white,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: context != null ? AppColors.borderOf(context) : _cardBorder),
  );
}

const EdgeInsets appointmentFlatPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 14);

Widget appointmentDoctorAvatar(String doctorName) {
  final initial = doctorName.trim().isNotEmpty ? doctorName.trim()[0].toUpperCase() : 'D';
  return CircleAvatar(
    radius: 20,
    backgroundColor: AppColors.patientTeal.withValues(alpha: 0.12),
    child: Text(
      initial,
      style: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppColors.patientTeal,
      ),
    ),
  );
}

Widget? appointmentDoctorRatingBadge(String doctorId) {
  final rating = RegisteredDoctorsStore.instance.findById(doctorId)?.rating;
  if (rating == null || rating <= 0) return null;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.star_rounded, size: 14, color: _starColor),
      const SizedBox(width: 2),
      Text(
        rating.toStringAsFixed(1),
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _starColor,
        ),
      ),
    ],
  );
}

Widget appointmentCardRating(double rating) {
  return Builder(
    builder: (context) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, size: 14, color: _starColor),
        const SizedBox(width: 2),
        Text(
          rating.toStringAsFixed(1),
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimaryOf(context),
            height: 1.2,
          ),
        ),
      ],
    ),
  );
}

ButtonStyle compactTealOutlinedButtonStyle() {
  return OutlinedButton.styleFrom(
    foregroundColor: AppColors.patientTeal,
    side: const BorderSide(color: AppColors.patientTeal),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    minimumSize: const Size(0, 32),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
  ).copyWith(
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.hovered) || states.contains(WidgetState.pressed)) {
        return AppColors.patientTeal.withValues(alpha: 0.08);
      }
      return null;
    }),
  );
}

ButtonStyle compactGhostButtonStyle() {
  return TextButton.styleFrom(
    foregroundColor: AppColors.textSecondary,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    minimumSize: const Size(0, 32),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
  );
}

Widget appointmentReviewStars(int rating, {double iconSize = 16}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: List.generate(5, (i) {
      return Icon(
        i < rating ? Icons.star_rounded : Icons.star_outline_rounded,
        size: iconSize,
        color: _starColor,
      );
    }),
  );
}

TextStyle appointmentCardDoctorNameStyle([BuildContext? context]) {
  return GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: context != null ? AppColors.textPrimaryOf(context) : AppColors.textPrimary,
  );
}

TextStyle appointmentCardDateStyle() {
  return GoogleFonts.inter(fontSize: 12, color: _textGray400, height: 1.35);
}

class AppointmentCardWrapper extends StatelessWidget {
  const AppointmentCardWrapper({
    super.key,
    required this.onTap,
    required this.child,
    this.flat = false,
    this.showDivider = false,
  });

  final VoidCallback onTap;
  final Widget child;
  final bool flat;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    if (flat) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: AppColors.surfaceOf(context),
            child: InkWell(
              onTap: onTap,
              child: Padding(padding: appointmentFlatPadding, child: child),
            ),
          ),
          if (showDivider) Divider(height: 1, thickness: 1, color: AppColors.borderOf(context)),
        ],
      );
    }

    return Material(
      color: AppColors.surfaceOf(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: appointmentTabCardDecoration(context),
          child: child,
        ),
      ),
    );
  }
}
