import '../../../../core/notifications/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'dart:async';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/session/doctor_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../data/doctor_profile_store.dart';
import '../models/doctor_profile_data.dart';
import '../../../../core/theme/app_typography.dart';

class ReviewsSection extends StatefulWidget {
  const ReviewsSection({super.key});

  @override
  State<ReviewsSection> createState() => _ReviewsSectionState();
}

enum ReviewSort { top, newest }

class _ReviewsSectionState extends State<ReviewsSection> {
  bool _loading = true;
  ReviewSort _reviewSort = ReviewSort.top;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshReviews());
  }

  Future<void> _refreshReviews() async {
    final doctorId = DoctorSession.loggedInDoctorId;
    if (doctorId.isNotEmpty) {
      await DoctorProfileStore.instance.loadReviews(doctorId);
    }
    if (mounted) setState(() => _loading = false);
  }

  List<PatientReview> get _reviews =>
      DoctorProfileStore.instance.profile.reviews;

  List<PatientReview> get _sortedReviews {
    final list = List<PatientReview>.from(_reviews);
    switch (_reviewSort) {
      case ReviewSort.newest:
        list.sort((a, b) => b.date.compareTo(a.date));
      case ReviewSort.top:
        list.sort((a, b) {
          int cmp = b.helpfulCount.compareTo(a.helpfulCount);
          if (cmp == 0) cmp = b.rating.compareTo(a.rating);
          if (cmp == 0) cmp = b.date.compareTo(a.date);
          return cmp;
        });
    }
    return list;
  }

  Map<int, int> get _breakdown {
    final counts = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
    for (final r in _reviews) {
      counts[r.rating] = (counts[r.rating] ?? 0) + 1;
    }
    return counts;
  }

  void _reply(PatientReview review) {
    final ctrl = TextEditingController(text: review.doctorReply ?? '');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reply to ${review.maskedName}'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: const InputDecoration(
              hintText: 'Write your reply...', alignLabelWithHint: true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              // FIXED: await the Firestore write; only mark replied + toast on confirmed save.
              final reply = ctrl.text.trim();
              final previous = review.doctorReply;
              setState(() => review.doctorReply = reply);
              try {
                await DoctorProfileStore.instance
                    .saveReply(reviewId: review.id, reply: reply);
              } catch (_) {
                if (!mounted) return; // FIXED: mounted check after await
                setState(() => review.doctorReply =
                    previous); // FIXED: roll back on failure
                AppToast.info(
                    context, 'Could not post reply. Please try again.');
                return;
              }
              if (!ctx.mounted)
                return; // FIXED: dialog context guard after await
              Navigator.pop(ctx);
            },
            child: const Text('Post Reply'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = DoctorProfileStore.instance.profile;
    final breakdown = _breakdown;
    final maxCount = breakdown.values.fold<int>(0, (a, b) => a > b ? a : b);

    return Scaffold(
      appBar: AppBar(title: const Text('Reviews')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.doctorBlue))
          : Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.cardBgOf(context),
                          borderRadius:
                              BorderRadius.circular(AppConstants.cardRadius),
                          border:
                              Border.all(color: AppColors.borderOf(context)),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '${p.rating}',
                              style: GoogleFonts.inter(
                                  fontSize: AppTypography.displayLarge,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.doctorBlue),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                  5,
                                  (i) => Icon(
                                        i < p.rating.round()
                                            ? Icons.star
                                            : Icons.star_border,
                                        color: const Color(0xFFF59E0B),
                                        size: 18,
                                      )),
                            ),
                            Text('${p.reviewCount} total reviews',
                                style: GoogleFonts.inter(
                                    fontSize: AppTypography.labelMedium,
                                    color: AppColors.textSecondaryOf(context))),
                            const SizedBox(height: 16),
                            ...List.generate(5, (i) {
                              final stars = 5 - i;
                              final count = breakdown[stars] ?? 0;
                              final fraction =
                                  maxCount == 0 ? 0.0 : count / maxCount;
                              return Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 3),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 28,
                                      child: Text('$stars★',
                                          style: GoogleFonts.inter(
                                              fontSize:
                                                  AppTypography.labelSmall)),
                                    ),
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: fraction,
                                          minHeight: 8,
                                          backgroundColor:
                                              AppColors.borderOf(context),
                                          color: AppColors.doctorBlue,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text('$count',
                                        style: GoogleFonts.inter(
                                            fontSize:
                                                AppTypography.labelSmall)),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: ReviewSort.values.map((s) {
                            final label = switch (s) {
                              ReviewSort.top => 'Top',
                              ReviewSort.newest => 'Newest',
                            };
                            final selected = _reviewSort == s;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(label),
                                selected: selected,
                                onSelected: (_) =>
                                    setState(() => _reviewSort = s),
                                selectedColor: AppColors.doctorBlue
                                    .withValues(alpha: 0.15),
                                checkmarkColor: AppColors.doctorBlue,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      ..._sortedReviews.map((r) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.cardBgOf(context),
                            borderRadius:
                                BorderRadius.circular(AppConstants.cardRadius),
                            border:
                                Border.all(color: AppColors.borderOf(context)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(r.maskedName,
                                        style: GoogleFonts.inter(
                                            fontWeight: FontWeight.w600)),
                                  ),
                                  Row(
                                    children: List.generate(
                                        5,
                                        (i) => Icon(
                                              i < r.rating
                                                  ? Icons.star
                                                  : Icons.star_border,
                                              size: 14,
                                              color: const Color(0xFFF59E0B),
                                            )),
                                  ),
                                ],
                              ),
                              Text(
                                DateFormat('dd MMM yyyy').format(r.date),
                                style: GoogleFonts.inter(
                                    fontSize: AppTypography.labelSmall,
                                    color: AppColors.textSecondaryOf(context)),
                              ),
                              const SizedBox(height: 8),
                              Text(r.text,
                                  style: GoogleFonts.inter(
                                      fontSize: AppTypography.bodySmall,
                                      height: 1.4)),
                              if (r.doctorReply != null) ...[
                                const SizedBox(height: 10),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppColors.doctorBlue
                                        .withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('Your reply',
                                          style: GoogleFonts.inter(
                                              fontSize:
                                                  AppTypography.labelSmall,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.doctorBlue)),
                                      Text(r.doctorReply!,
                                          style: GoogleFonts.inter(
                                              fontSize:
                                                  AppTypography.labelMedium)),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () => _reply(r),
                                  child: Text(r.doctorReply == null
                                      ? 'Reply'
                                      : 'Edit Reply'),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
