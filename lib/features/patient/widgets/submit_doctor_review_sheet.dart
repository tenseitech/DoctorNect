import '../../../core/notifications/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

/// Bottom sheet for submitting or editing a doctor review (editable for 48 hours).
abstract final class SubmitDoctorReviewSheet {
  static Future<bool?> show(
    BuildContext context, {
    required String doctorName,
    required Future<bool> Function(int rating, String comment) onSubmit,
    int? initialRating,
    String? initialComment,
    bool isEdit = false,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _SubmitDoctorReviewBody(
        doctorName: doctorName,
        onSubmit: onSubmit,
        initialRating: initialRating,
        initialComment: initialComment,
        isEdit: isEdit,
      ),
    );
  }
}

class _SubmitDoctorReviewBody extends StatefulWidget {
  const _SubmitDoctorReviewBody({
    required this.doctorName,
    required this.onSubmit,
    this.initialRating,
    this.initialComment,
    this.isEdit = false,
  });

  final String doctorName;
  final Future<bool> Function(int rating, String comment) onSubmit;
  final int? initialRating;
  final String? initialComment;
  final bool isEdit;

  @override
  State<_SubmitDoctorReviewBody> createState() =>
      _SubmitDoctorReviewBodyState();
}

class _SubmitDoctorReviewBodyState extends State<_SubmitDoctorReviewBody> {
  late int _rating;
  late final TextEditingController _commentController;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _rating = widget.initialRating ?? 0;
    final initialComment = widget.initialComment?.trim();
    _commentController = TextEditingController(
      text: initialComment == null || initialComment == 'No written comment.'
          ? ''
          : initialComment,
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating < 1 || _submitting) return;
    setState(() => _submitting = true);
    final ok = await widget.onSubmit(_rating, _commentController.text.trim());
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _submitting = false);
      AppToast.info(
        context,
        widget.isEdit
            ? 'Could not update review. Edits are allowed within 48 hours.'
            : 'Could not submit review. Please try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.isEdit
                ? 'Edit your review'
                : 'Rate Dr. ${widget.doctorName}',
            style: GoogleFonts.inter(
                fontSize: AppTypography.headlineMedium,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            widget.isEdit
                ? 'You can edit this review within 48 hours of posting.'
                : 'How was your visit?',
            style: GoogleFonts.inter(
                fontSize: AppTypography.bodyMedium,
                color: AppColors.textSecondaryOf(context)),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final starIndex = i + 1;
              final filled = starIndex <= _rating;
              return IconButton(
                tooltip: '$starIndex star${starIndex == 1 ? '' : 's'}',
                onPressed: _submitting
                    ? null
                    : () => setState(() => _rating = starIndex),
                icon: Icon(
                  filled ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 40,
                  color: const Color(0xFFF59E0B),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _commentController,
            enabled: !_submitting,
            maxLines: 4,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Share your experience (optional)',
              hintStyle:
                  GoogleFonts.inter(color: AppColors.textSecondaryOf(context)),
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _rating < 1 || _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.patientTeal,
              foregroundColor: AppColors.white,
              minimumSize: const Size(double.infinity, 48),
            ),
            child: _submitting
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.white),
                  )
                : Text(widget.isEdit ? 'Save changes' : 'Submit'),
          ),
        ],
      ),
    );
  }
}
