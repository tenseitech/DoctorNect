import '../../../../core/notifications/app_toast.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'dart:async';

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
            hintText: 'Write your reply...',
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              // FIXED: await the Firestore write; only mark replied + toast on confirmed save.
              final reply = ctrl.text.trim();
              final previous = review.doctorReply;
              setState(() => review.doctorReply = reply);
              try {
                await DoctorProfileStore.instance.saveReply(
                  reviewId: review.id,
                  reply: reply,
                );
              } catch (_) {
                if (!mounted) return; // FIXED: mounted check after await
                setState(
                  () => review.doctorReply = previous,
                ); // FIXED: roll back on failure
                AppToast.info(
                  context,
                  'Could not post reply. Please try again.',
                );
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
    final sortedReviews = _sortedReviews;

    return Scaffold(
      appBar: AppBar(title: const Text('Reviews')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.doctorBlue),
            )
          : Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Rating Summary Stat Block
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceOf(context),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.borderOf(context),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  '${p.rating}',
                                  style: TextStyle(fontFamily: 'Inter', 
                                    fontSize: AppTypography.displayLarge,
                                    fontWeight: FontWeight.w800,
                                    height: 1.0,
                                    color: AppColors.doctorBlue,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: List.generate(
                                          5,
                                          (i) => Padding(
                                            padding: const EdgeInsets.only(
                                              right: 2,
                                            ),
                                            child: Icon(
                                              i < p.rating.round()
                                                  ? Icons.star_rounded
                                                  : Icons.star_border_rounded,
                                              color: const Color(0xFFF59E0B),
                                              size: 20,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${p.reviewCount} total reviews',
                                        style: TextStyle(fontFamily: 'Inter', 
                                          fontSize: AppTypography.labelMedium,
                                          color: AppColors.textSecondaryOf(
                                            context,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Divider(
                              height: 1,
                              color: AppColors.borderOf(context),
                            ),
                            const SizedBox(height: 12),
                            ...List.generate(5, (i) {
                              final stars = 5 - i;
                              final count = breakdown[stars] ?? 0;
                              final fraction =
                                  maxCount == 0 ? 0.0 : count / maxCount;
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4.5,
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 30,
                                      child: Text(
                                        '$stars★',
                                        style: TextStyle(fontFamily: 'Inter', 
                                          fontSize: AppTypography.labelSmall,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textSecondaryOf(
                                            context,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: LinearProgressIndicator(
                                        value: fraction,
                                        minHeight: 8,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        backgroundColor: AppColors.borderOf(
                                          context,
                                        ),
                                        color: AppColors.doctorBlue,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    SizedBox(
                                      width: 22,
                                      child: Text(
                                        '$count',
                                        textAlign: TextAlign.right,
                                        style: TextStyle(fontFamily: 'Inter', 
                                          fontSize: AppTypography.labelSmall,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textSecondaryOf(
                                            context,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Consistent Pill Filter Chips
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
                                showCheckmark: false,
                                onSelected: (_) =>
                                    setState(() => _reviewSort = s),
                                shape: const StadiumBorder(),
                                side: BorderSide(
                                  color: selected
                                      ? AppColors.doctorBlue
                                      : AppColors.borderOf(context),
                                  width: 1.2,
                                ),
                                backgroundColor: AppColors.surfaceOf(context),
                                selectedColor: AppColors.doctorBlue,
                                labelStyle: TextStyle(fontFamily: 'Inter', 
                                  fontSize: AppTypography.bodySmall,
                                  fontWeight: FontWeight.w600,
                                  color: selected
                                      ? Colors.white
                                      : AppColors.textSecondaryOf(context),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 6,
                                ),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Review Cards List
                      for (var idx = 0; idx < sortedReviews.length; idx++) ...[
                        if (idx > 0)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Divider(
                              height: 1,
                              color: AppColors.borderOf(context)
                                  .withValues(alpha: 0.6),
                            ),
                          ),
                        _buildReviewCard(context, sortedReviews[idx]),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildReviewCard(BuildContext context, PatientReview r) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderOf(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ReviewerAvatar(name: r.maskedName),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      r.maskedName,
                      style: TextStyle(fontFamily: 'Inter', 
                        fontWeight: FontWeight.w600,
                        fontSize: AppTypography.bodySmall,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      DateFormat('dd MMM yyyy').format(r.date),
                      style: TextStyle(fontFamily: 'Inter', 
                        fontSize: AppTypography.labelSmall,
                        color: AppColors.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < r.rating ? Icons.star : Icons.star_border,
                    size: 14,
                    color: const Color(0xFFF59E0B),
                  ),
                ),
              ),
            ],
          ),
          if (r.text.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              r.text,
              style: TextStyle(fontFamily: 'Inter', 
                fontSize: AppTypography.bodySmall,
                height: 1.38,
                color: AppColors.textPrimaryOf(context),
              ),
            ),
          ],
          if (r.doctorReply != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.doctorBlue.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your reply',
                    style: TextStyle(fontFamily: 'Inter', 
                      fontSize: AppTypography.labelSmall,
                      fontWeight: FontWeight.w600,
                      color: AppColors.doctorBlue,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    r.doctorReply!,
                    style: TextStyle(fontFamily: 'Inter', 
                      fontSize: AppTypography.labelMedium,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              onPressed: () => _reply(r),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                foregroundColor: AppColors.doctorBlue,
                side: BorderSide(
                  color: AppColors.doctorBlue.withValues(alpha: 0.45),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: TextStyle(fontFamily: 'Inter', 
                  fontSize: AppTypography.labelSmall,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(r.doctorReply == null ? 'Reply' : 'Edit Reply'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewerAvatar extends StatelessWidget {
  const _ReviewerAvatar({required this.name});

  final String name;

  static const List<Color> _palette = [
    AppColors.doctorBlue,
    Color(0xFF0D9488),
    Color(0xFF7C3AED),
    Color(0xFFEA580C),
    Color(0xFF16A34A),
    Color(0xFFDB2777),
  ];

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isNotEmpty ? trimmed[0].toUpperCase() : '?';
    final hash = trimmed.codeUnits.fold<int>(0, (acc, c) => acc + c);
    final color = _palette[hash % _palette.length];

    return CircleAvatar(
      radius: 18,
      backgroundColor: color.withValues(alpha: 0.14),
      child: Text(
        initial,
        style: TextStyle(fontFamily: 'Inter', 
          fontSize: AppTypography.bodySmall,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
