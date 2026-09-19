import '../../../core/firebase/firestore_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../widgets/overflow_safe_layout.dart';
import '../../../core/theme/app_typography.dart';

/// Shows a star-rating dialog and saves the rating to Firestore + local store.
Future<bool> showAmbulanceRatingDialog({
  required BuildContext context,
  required String bookingId,
  required String ambulanceName,
}) async {
  int selectedStars = 0;
  final reviewCtrl = TextEditingController();

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            content: scrollableDialogContent(
              context: ctx,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.local_hospital,
                      color: Color(0xFFDC2626),
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Rate your experience',
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.headlineSmall,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ambulanceName,
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.bodySmall,
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Stars
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final starIndex = i + 1;
                      return GestureDetector(
                        onTap: () =>
                            setDialogState(() => selectedStars = starIndex),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: AnimatedScale(
                            scale: selectedStars >= starIndex ? 1.15 : 1.0,
                            duration: const Duration(milliseconds: 150),
                            child: Icon(
                              selectedStars >= starIndex
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              size: 40,
                              color: selectedStars >= starIndex
                                  ? const Color(0xFFF59E0B)
                                  : AppColors.borderOf(context),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),

                  const SizedBox(height: 8),
                  if (selectedStars > 0)
                    Text(
                      _ratingLabel(selectedStars),
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodySmall,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFFF59E0B),
                      ),
                    ),

                  const SizedBox(height: 16),

                  // Review text field
                  TextField(
                    controller: reviewCtrl,
                    maxLines: 2,
                    maxLength: 200,
                    style:
                        GoogleFonts.inter(fontSize: AppTypography.bodyMedium),
                    decoration: InputDecoration(
                      hintText: 'Write a short review (optional)',
                      hintStyle: GoogleFonts.inter(
                        fontSize: AppTypography.bodySmall,
                        color: AppColors.textSecondaryOf(context),
                      ),
                      counterText: '',
                      filled: true,
                      fillColor: AppColors.cardBgOf(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: AppColors.borderOf(context)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: AppColors.borderOf(context)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFFF59E0B),
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Skip'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: selectedStars > 0
                          ? () async {
                              final ok = await FirestoreService
                                  .instance.ambulance
                                  .rateBroadcast(
                                broadcastId: bookingId,
                                stars: selectedStars,
                                review: reviewCtrl.text.trim().isEmpty
                                    ? null
                                    : reviewCtrl.text.trim(),
                              );
                              if (ctx.mounted) Navigator.pop(ctx, ok);
                            }
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFF59E0B),
                        disabledBackgroundColor:
                            const Color(0xFFF59E0B).withValues(alpha: 0.3),
                        minimumSize: const Size(0, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Submit'),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      );
    },
  );

  reviewCtrl.dispose();
  return result == true;
}

String _ratingLabel(int stars) => switch (stars) {
      1 => 'Poor',
      2 => 'Below Average',
      3 => 'Average',
      4 => 'Good',
      5 => 'Excellent!',
      _ => '',
    };
