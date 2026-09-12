import '../../../core/firebase/firestore_service.dart';
import '../../../core/notifications/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/layout/responsive_layout.dart';
import '../../../core/data/doctor_patient_stats_service.dart';
import '../../../core/data/shared_appointments_store.dart';
import '../../../core/session/doctor_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/external_launcher.dart';
import 'dart:async';

import '../../../core/session/patient_session.dart';
import '../../doctor/profile/data/doctor_photo_local_store.dart';
import '../../doctor/profile/data/doctor_profile_store.dart';
import '../appointments/models/patient_appointment_models.dart';
import '../data/featured_doctors_service.dart';
import '../booking/booking_flow_screen.dart';
import '../widgets/submit_doctor_review_sheet.dart';
import 'widgets/doctor_profile_share_sheet.dart';
import 'widgets/patient_doctor_profile_hero.dart';
import 'widgets/patient_doctor_profile_shared.dart';
import 'models/doctor_profile_detail.dart';
import 'data/review_vote_store.dart';

class PatientDoctorProfileScreen extends StatefulWidget {
  const PatientDoctorProfileScreen({super.key, required this.doctorId});

  final String doctorId;

  @override
  State<PatientDoctorProfileScreen> createState() => _PatientDoctorProfileScreenState();
}

class _PatientDoctorProfileScreenState extends State<PatientDoctorProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  ReviewSort _reviewSort = ReviewSort.top;
  late Future<DoctorProfileDetail?> _doctorFuture;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _doctorFuture = FirestoreService.instance.doctorProfileDetail.fetch(widget.doctorId);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openBooking() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingFlowScreen(doctorId: widget.doctorId),
      ),
    );
  }

  PatientAppointment? _reviewableVisit() {
    for (final a in SharedAppointmentsStore.instance.patientAppointments()) {
      if (a.doctorId != widget.doctorId) continue;
      if (a.cancellationReason != null) continue;
      if (a.hasReview) continue;
      if (a.dateTime.isBefore(DateTime.now().subtract(const Duration(hours: 1)))) {
        return a;
      }
    }
    return null;
  }

  Future<void> _rateDoctorDirectly(String doctorName) async {
    final patientId = PatientSession.loggedInPatientId;
    if (patientId.isEmpty) {
      AppToast.info(context, 'Please sign in as a patient to rate & review doctors.');
      return;
    }
    PatientDoctorReview? existingReview;
    if (patientId.isNotEmpty) {
      existingReview = await FirestoreService.instance.review.fetchReviewForPatientAndDoctor(
        patientId: patientId,
        doctorId: widget.doctorId,
      );
    }
    if (!mounted) return;

    final isEdit = existingReview != null;
    final submitted = await SubmitDoctorReviewSheet.show(
      context,
      doctorName: doctorName,
      isEdit: isEdit,
      initialRating: existingReview?.rating,
      initialComment: existingReview?.text,
      onSubmit: (rating, comment) async {
        final reviewId = await FirestoreService.instance.review.submitReview(
          patientId: patientId,
          doctorId: widget.doctorId,
          appointmentId: '',
          rating: rating,
          comment: comment,
          patientName: PatientSession.loggedInPatientName,
        );
        return reviewId != null;
      },
    );
    if (!mounted || submitted != true) return;
    setState(() {
      _doctorFuture = FirestoreService.instance.doctorProfileDetail.fetch(widget.doctorId);
    });
    AppToast.info(
      context,
      isEdit ? 'Review updated' : 'Thank you for your review! It is now visible to everyone.',
    );
  }

  Future<void> _editReview(PatientDoctorReview review, String doctorName) async {
    final submitted = await SubmitDoctorReviewSheet.show(
      context,
      doctorName: doctorName,
      isEdit: true,
      initialRating: review.rating,
      initialComment: review.text,
      onSubmit: (rating, comment) => SharedAppointmentsStore.instance.updateReviewByReviewId(
        reviewId: review.id,
        rating: rating,
        comment: comment,
      ),
    );
    if (!mounted || submitted != true) return;
    setState(() {
      _doctorFuture = FirestoreService.instance.doctorProfileDetail.fetch(widget.doctorId);
    });
    AppToast.info(context, 'Review updated');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DoctorProfileDetail?>(
      future: _doctorFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: AppColors.patientTeal)),
          );
        }

        final doctor = snapshot.data;
        if (doctor == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Doctor not found')),
          );
        }

        return ListenableBuilder(
          listenable: SharedAppointmentsStore.instance,
          builder: (context, _) {
            return _DoctorProfileBody(
              doctor: doctor,
              tabController: _tabController,
              reviewSort: _reviewSort,
              onReviewSortChanged: (sort) => setState(() => _reviewSort = sort),
              onBook: _openBooking,
              reviewableVisit: _reviewableVisit(),
              onRateDoctor: () => _rateDoctorDirectly(doctor.name),
              onEditReview: _editReview,
            );
          },
        );
      },
    );
  }
}

class _DoctorProfileBody extends StatelessWidget {
  const _DoctorProfileBody({
    required this.doctor,
    required this.tabController,
    required this.reviewSort,
    required this.onReviewSortChanged,
    required this.onBook,
    required this.reviewableVisit,
    required this.onRateDoctor,
    required this.onEditReview,
  });

  final DoctorProfileDetail doctor;
  final TabController tabController;
  final ReviewSort reviewSort;
  final ValueChanged<ReviewSort> onReviewSortChanged;
  final VoidCallback onBook;
  final PatientAppointment? reviewableVisit;
  final VoidCallback onRateDoctor;
  final void Function(PatientDoctorReview review, String doctorName) onEditReview;

  @override
  Widget build(BuildContext context) {
    final isPatientView = DoctorSession.loggedInDoctorId.isEmpty;
    final compact = ResponsiveLayout.isCompact(context);

    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceOf(context),
        foregroundColor: AppColors.textPrimaryOf(context),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Doctor Profile',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        centerTitle: true,
      ),
      bottomNavigationBar: isPatientView && compact
          ? PatientDoctorProfileBottomBar(onBook: onBook)
          : null,
      body: _DoctorProfileScrollBody(
        doctor: doctor,
        tabController: tabController,
        reviewSort: reviewSort,
        onReviewSortChanged: onReviewSortChanged,
        isPatientView: isPatientView,
        compact: compact,
        onBook: onBook,
        onCall: () => ExternalLauncher.callPhone(doctor.phone, context: context),
        onShare: () => DoctorProfileShareSheet.show(context, doctor),
        reviewableVisit: reviewableVisit,
        onRateDoctor: isPatientView ? onRateDoctor : null,
        onEditReview: (review) => onEditReview(review, doctor.name),
      ),
    );
  }
}

class _DoctorProfileScrollBody extends StatefulWidget {
  const _DoctorProfileScrollBody({
    required this.doctor,
    required this.tabController,
    required this.reviewSort,
    required this.onReviewSortChanged,
    required this.isPatientView,
    required this.compact,
    required this.onBook,
    required this.onCall,
    required this.onShare,
    required this.reviewableVisit,
    required this.onRateDoctor,
    required this.onEditReview,
  });

  final DoctorProfileDetail doctor;
  final TabController tabController;
  final ReviewSort reviewSort;
  final ValueChanged<ReviewSort> onReviewSortChanged;
  final bool isPatientView;
  final bool compact;
  final VoidCallback onBook;
  final VoidCallback onCall;
  final VoidCallback onShare;
  final PatientAppointment? reviewableVisit;
  final VoidCallback? onRateDoctor;
  final ValueChanged<PatientDoctorReview> onEditReview;

  @override
  State<_DoctorProfileScrollBody> createState() => _DoctorProfileScrollBodyState();
}

class _DoctorProfileScrollBodyState extends State<_DoctorProfileScrollBody> {
  @override
  void initState() {
    super.initState();
    widget.tabController.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    widget.tabController.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (widget.tabController.indexIsChanging == false) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 600;

    // On tablet/desktop center the content with a max-width constraint.
    // On mobile let it fill the screen (horizontalPad = 0).
    final double contentMax = isCompact ? screenWidth : 680.0;
    final double hPad = ((screenWidth - contentMax) / 2).clamp(0.0, double.infinity);

    return ListView(
      padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 24),
      children: [
        PatientDoctorProfileHero(
          doctor: widget.doctor,
          avatar: _HeroAvatar(doctor: widget.doctor),
          reviewableVisit: widget.reviewableVisit,
          onRateDoctor: widget.isPatientView ? widget.onRateDoctor : null,
          onBook: widget.isPatientView ? widget.onBook : null,
          onCall: widget.onCall,
          onShare: widget.onShare,
        ),
        const SizedBox(height: 8),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 20, vertical: 8),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.surfaceOf(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderOf(context)),
            ),
            child: TabBar(
              controller: widget.tabController,
              labelColor: AppColors.textPrimaryOf(context),
              unselectedLabelColor: AppColors.textSecondaryOf(context),
              indicator: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF334155)
                    : AppColors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              isScrollable: isCompact,
              tabAlignment: isCompact ? TabAlignment.start : TabAlignment.fill,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicatorPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              labelPadding: EdgeInsets.symmetric(horizontal: isCompact ? 12 : 20),
              labelStyle: GoogleFonts.inter(
                fontSize: isCompact ? 13 : 14,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: GoogleFonts.inter(
                fontSize: isCompact ? 13 : 14,
                fontWeight: FontWeight.w500,
              ),
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'Experience'),
                Tab(text: 'Reviews'),
                Tab(text: 'Location'),
              ],
            ),
          ),
        ),
        _ProfileTabPanel(
          index: widget.tabController.index,
          doctor: widget.doctor,
          reviewSort: widget.reviewSort,
          onReviewSortChanged: widget.onReviewSortChanged,
          onEditReview: widget.onEditReview,
          onRateDoctor: widget.onRateDoctor,
        ),
      ],
    );
  }
}


class _ProfileTabPanel extends StatelessWidget {
  const _ProfileTabPanel({
    required this.index,
    required this.doctor,
    required this.reviewSort,
    required this.onReviewSortChanged,
    required this.onEditReview,
    this.onRateDoctor,
  });

  final int index;
  final DoctorProfileDetail doctor;
  final ReviewSort reviewSort;
  final ValueChanged<ReviewSort> onReviewSortChanged;
  final ValueChanged<PatientDoctorReview> onEditReview;
  final VoidCallback? onRateDoctor;

  @override
  Widget build(BuildContext context) {
    return switch (index) {
      0 => _OverviewTab(doctor: doctor),
      1 => _ExperienceTab(doctor: doctor),
      2 => _ReviewsTab(
          doctor: doctor,
          sort: reviewSort,
          onSort: onReviewSortChanged,
          onEditReview: onEditReview,
          onRateDoctor: onRateDoctor,
        ),
      _ => _LocationTab(doctor: doctor),
    };
  }
}

enum ReviewSort { top, newest }

/// Own locally stored photo when viewing their own profile, else initial.
class _HeroAvatar extends StatefulWidget {
  const _HeroAvatar({required this.doctor});

  final DoctorProfileDetail doctor;

  @override
  State<_HeroAvatar> createState() => _HeroAvatarState();
}

class _HeroAvatarState extends State<_HeroAvatar> {
  Uint8List? _localBytes;

  @override
  void initState() {
    super.initState();
    _resolveLocal();
  }

  bool get _isOwnProfile =>
      widget.doctor.id.isNotEmpty &&
      widget.doctor.id == DoctorSession.loggedInDoctorId;

  Future<void> _resolveLocal() async {
    final url = widget.doctor.photoUrl;
    if (url != null && url.trim().isNotEmpty) return;
    if (!_isOwnProfile) return;

    final profileBytes = DoctorProfileStore.instance.profile.photoBytes;
    if (profileBytes != null && profileBytes.isNotEmpty) {
      setState(() => _localBytes = profileBytes);
      return;
    }
    final bytes = await DoctorPhotoLocalStore.load(widget.doctor.id);
    if (bytes != null && bytes.isNotEmpty && mounted) {
      setState(() => _localBytes = bytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.doctor.photoUrl;
    ImageProvider? provider;
    if (url != null && url.trim().isNotEmpty) {
      provider = NetworkImage(url.trim());
    } else if (_localBytes != null && _localBytes!.isNotEmpty) {
      provider = MemoryImage(_localBytes!);
    }

    final name = widget.doctor.name;
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'D';

    return CircleAvatar(
      radius: 44,
      backgroundColor: AppColors.patientTeal.withValues(alpha: 0.1),
      backgroundImage: provider,
      onBackgroundImageError: provider != null ? (_, __) {} : null,
      child: provider == null
          ? Text(
              initial,
              style: GoogleFonts.inter(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                color: AppColors.patientTeal,
              ),
            )
          : null,
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.doctor});

  final DoctorProfileDetail doctor;

  @override
  Widget build(BuildContext context) {
    final isDoctorViewing = DoctorSession.loggedInDoctorId.isNotEmpty;

    return patientDoctorTabList(
      context,
      pageKey: 'overview',
      scrollable: false,
      children: [
        if (isDoctorViewing) ...[
          _DoctorPerformanceStats(doctorId: doctor.id),
          const SizedBox(height: 10),
        ],
        PatientDoctorContentCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PatientDoctorSectionTitle('About'),
              Text(
                doctor.about.trim().isEmpty ? 'Bio not added yet.' : doctor.about,
                style: GoogleFonts.inter(fontSize: 14, height: 1.6, color: AppColors.textSecondaryOf(context)),
              ),
            ],
          ),
        ),
        PatientDoctorContentCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PatientDoctorSectionTitle('Specialities'),
              PatientDoctorTagWrap(items: doctor.specialities),
            ],
          ),
        ),
        PatientDoctorContentCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PatientDoctorSectionTitle('Services offered'),
              PatientDoctorTagWrap(items: doctor.services),
            ],
          ),
        ),
        if (!isDoctorViewing)
          PatientDoctorContentCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PatientDoctorSectionTitle('Clinic timings'),
                _ClinicTimingsTable(timings: doctor.timings),
              ],
            ),
          ),
      ],
    );
  }
}

class _DoctorPerformanceStats extends StatefulWidget {
  const _DoctorPerformanceStats({required this.doctorId});

  final String doctorId;

  @override
  State<_DoctorPerformanceStats> createState() =>
      _DoctorPerformanceStatsState();
}

class _DoctorPerformanceStatsState extends State<_DoctorPerformanceStats> {
  static const _periods = [
    ('Today', FeaturedDoctorPeriod.day),
    ('This Week', FeaturedDoctorPeriod.week),
    ('This Month', FeaturedDoctorPeriod.month),
    ('This Year', FeaturedDoctorPeriod.year),
  ];

  int _selectedIndex = 2; // default: This Month

  @override
  Widget build(BuildContext context) {
    final period = _periods[_selectedIndex];
    final since = FeaturedDoctorsService.periodStartFor(period.$2);
    final stats =
        DoctorPatientStatsService.statsForDoctor(widget.doctorId, since);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PatientDoctorSectionTitle('Performance Stats'),
        const SizedBox(height: 4),
        // Period selector chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(_periods.length, (i) {
              final selected = i == _selectedIndex;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(_periods[i].$1),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedIndex = i),
                  selectedColor:
                      AppColors.patientTeal.withValues(alpha: 0.15),
                  checkmarkColor: AppColors.patientTeal,
                  labelStyle: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected
                        ? AppColors.patientTeal
                        : AppColors.textSecondaryOf(context),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 14),
        // Stats cards row
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.people_outline,
                value: '${stats.patientsTreated}',
                label: 'Patients\nTreated',
                color: const Color(0xFF2563EB),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                icon: Icons.chat_bubble_outline,
                value: '${stats.consultationCount}',
                label: 'Consultations',
                color: const Color(0xFF16A34A),
              ),
            ),
          ],
        ),
        // Services used
        if (stats.services.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            'Services used in this period',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: stats.services.map((service) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.patientTeal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.patientTeal.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _serviceIcon(service),
                      size: 14,
                      color: AppColors.patientTeal,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      service,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.patientTeal,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
        if (stats.patientsTreated == 0 && stats.consultationCount == 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'No activity recorded for this period yet.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
          ),
      ],
    );
  }

  static IconData _serviceIcon(String service) {
    final lower = service.toLowerCase();
    if (lower.contains('prescription')) return AppIcons.prescription;
    if (lower.contains('lab')) return Icons.biotech_outlined;
    if (lower.contains('follow')) return Icons.replay_outlined;
    if (lower.contains('new visit')) return Icons.person_add_outlined;
    return Icons.medical_services_outlined;
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondaryOf(context),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExperienceTab extends StatelessWidget {
  const _ExperienceTab({required this.doctor});

  final DoctorProfileDetail doctor;

  @override
  Widget build(BuildContext context) {
    return patientDoctorTabList(
      context,
      pageKey: 'experience',
      scrollable: false,
      children: [
        Text(
          '${doctor.experienceYears} years of experience in ${doctor.specialization}',
          style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondaryOf(context), height: 1.5),
        ),
        const SizedBox(height: 24),
        _ExperienceSection(
          title: 'Education',
          emptyMessage: 'Education details not added yet.',
          children: doctor.education
              .map(
                (e) => PatientDoctorTimelineTile(
                  title: e.degree,
                  subtitle: _educationSubtitle(e),
                ),
              )
              .toList(),
        ),
        _ExperienceSection(
          title: 'Past hospitals / clinics',
          emptyMessage: 'Workplace history not added yet.',
          children: cleanProfileLabels(doctor.pastWorkplaces)
              .map((w) => PatientDoctorBulletItem(w))
              .toList(),
        ),
        _ExperienceSection(
          title: 'Awards & recognitions',
          emptyMessage: 'No awards listed yet.',
          children: cleanProfileLabels(doctor.awards).map((a) => PatientDoctorBulletItem(a)).toList(),
        ),
        _ExperienceSection(
          title: 'Publications',
          emptyMessage: 'No publications listed yet.',
          children:
              cleanProfileLabels(doctor.publications).map((p) => PatientDoctorBulletItem(p)).toList(),
        ),
        _ExperienceSection(
          title: 'Memberships',
          emptyMessage: 'Membership details not added yet.',
          children:
              cleanProfileLabels(doctor.memberships).map((m) => PatientDoctorBulletItem(m)).toList(),
        ),
      ],
    );
  }

  String _educationSubtitle(EducationEntry entry) {
    final parts = <String>[
      if (entry.college.trim().isNotEmpty) entry.college.trim(),
      if (entry.year > 0) '${entry.year}',
    ];
    return parts.isEmpty ? 'Qualification' : parts.join(' · ');
  }
}

class _ExperienceSection extends StatelessWidget {
  const _ExperienceSection({
    required this.title,
    required this.emptyMessage,
    required this.children,
  });

  final String title;
  final String emptyMessage;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PatientDoctorSectionTitle(title),
        if (children.isEmpty)
          Text(
            emptyMessage,
            style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondaryOf(context)),
          )
        else
          ...children,
        const SizedBox(height: 20),
      ],
    );
  }
}

class _ReviewsTab extends StatefulWidget {
  const _ReviewsTab({
    required this.doctor,
    required this.sort,
    required this.onSort,
    required this.onEditReview,
    this.onRateDoctor,
  });

  final DoctorProfileDetail doctor;
  final ReviewSort sort;
  final ValueChanged<ReviewSort> onSort;
  final ValueChanged<PatientDoctorReview> onEditReview;
  final VoidCallback? onRateDoctor;

  @override
  State<_ReviewsTab> createState() => _ReviewsTabState();
}

class _ReviewsTabState extends State<_ReviewsTab> {
  final Set<String> _likedReviewIds = {};
  final Map<String, int> _helpfulCounts = {};
  bool _loadingVotes = true;
  final Set<String> _togglingReviewIds = {};

  @override
  void initState() {
    super.initState();
    unawaited(_loadVoteState());
  }

  @override
  void didUpdateWidget(covariant _ReviewsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.doctor.reviews != widget.doctor.reviews) {
      _syncCountsFromReviews();
      unawaited(_loadVoteState());
    }
  }

  void _syncCountsFromReviews() {
    for (final review in widget.doctor.reviews) {
      _helpfulCounts.putIfAbsent(review.id, () => review.helpfulCount);
    }
  }

  Future<void> _loadVoteState() async {
    _syncCountsFromReviews();
    final reviewIds = widget.doctor.reviews.map((r) => r.id).toList();
    if (reviewIds.isEmpty) {
      if (mounted) setState(() => _loadingVotes = false);
      return;
    }

    final patientId = PatientSession.loggedInPatientId;
    Set<String> liked = const {};
    if (patientId.isNotEmpty) {
      liked = await FirestoreService.instance.review.likedReviewIdsForPatient(
        patientId: patientId,
        reviewIds: reviewIds,
      );
      if (liked.isEmpty) {
        liked = await ReviewVoteStore.likedReviewIds(reviewIds);
      }
    } else {
      liked = await ReviewVoteStore.likedReviewIds(reviewIds);
    }

    if (!mounted) return;
    setState(() {
      _likedReviewIds
        ..clear()
        ..addAll(liked);
      _loadingVotes = false;
    });
  }

  int _displayHelpfulCount(PatientDoctorReview review) {
    return _helpfulCounts[review.id] ?? review.helpfulCount;
  }

  Future<void> _toggleLike(PatientDoctorReview review) async {
    if (_togglingReviewIds.contains(review.id)) return;

    final patientId = PatientSession.loggedInPatientId;
    final wasLiked = _likedReviewIds.contains(review.id);
    final previousCount = _displayHelpfulCount(review);

    setState(() {
      _togglingReviewIds.add(review.id);
      if (wasLiked) {
        _likedReviewIds.remove(review.id);
        _helpfulCounts[review.id] = previousCount > 0 ? previousCount - 1 : 0;
      } else {
        _likedReviewIds.add(review.id);
        _helpfulCounts[review.id] = previousCount + 1;
      }
    });

    bool? remoteLiked;
    if (patientId.isNotEmpty) {
      remoteLiked = await FirestoreService.instance.review.toggleHelpfulVote(
        reviewId: review.id,
        patientId: patientId,
      );
    } else {
      remoteLiked = !wasLiked;
    }

    if (!mounted) return;

    if (remoteLiked == null) {
      setState(() {
        if (wasLiked) {
          _likedReviewIds.add(review.id);
        } else {
          _likedReviewIds.remove(review.id);
        }
        _helpfulCounts[review.id] = previousCount;
        _togglingReviewIds.remove(review.id);
      });
      AppToast.info(context, 'Could not update like. Please try again.');
      return;
    }

    await ReviewVoteStore.setLiked(review.id, remoteLiked);
    if (!mounted) return;
    setState(() => _togglingReviewIds.remove(review.id));
  }

  List<PatientDoctorReview> get _sorted {
    final list = List<PatientDoctorReview>.from(widget.doctor.reviews);
    switch (widget.sort) {
      case ReviewSort.newest:
        list.sort((a, b) => b.date.compareTo(a.date));
      case ReviewSort.top:
        list.sort((a, b) {
          int cmp = _displayHelpfulCount(b).compareTo(_displayHelpfulCount(a));
          if (cmp == 0) cmp = b.rating.compareTo(a.rating);
          if (cmp == 0) cmp = b.date.compareTo(a.date);
          return cmp;
        });
    }
    return list;
  }

  Map<int, int> get _breakdown {
    final counts = {5: 0, 4: 0, 3: 0, 2: 0, 1: 0};
    for (final r in widget.doctor.reviews) {
      counts[r.rating] = (counts[r.rating] ?? 0) + 1;
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.doctor.reviews.length;
    final breakdown = _breakdown;

    if (total == 0) {
      return patientDoctorTabList(
        context,
        pageKey: 'reviews-empty',
        scrollable: false,
        children: [
          Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.patientTeal.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.rate_review_outlined,
                  size: 36,
                  color: AppColors.patientTeal.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'No reviews yet',
                style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Be the first to share your experience after a visit.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondaryOf(context), height: 1.4),
              ),
              const SizedBox(height: 20),
              if (widget.onRateDoctor != null)
                ElevatedButton.icon(
                  onPressed: widget.onRateDoctor,
                  icon: const Icon(Icons.star_rounded, size: 20),
                  label: const Text('Write a Review & Rate Doctor'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.patientTeal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
            ],
          ),
        ],
      );
    }

    return patientDoctorTabList(
      context,
      pageKey: 'reviews',
      scrollable: false,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardBgOf(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Row(
            children: [
              Column(
                children: [
                  Text(
                    widget.doctor.rating.toStringAsFixed(1),
                    style: GoogleFonts.inter(
                      fontSize: 42,
                      fontWeight: FontWeight.w800,
                      color: AppColors.patientTeal,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: List.generate(5, (i) {
                      return Icon(
                        i < widget.doctor.rating.round() ? Icons.star_rounded : Icons.star_outline_rounded,
                        size: 16,
                        color: const Color(0xFFF59E0B),
                      );
                    }),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$total reviews',
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
                  ),
                ],
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  children: [5, 4, 3, 2, 1].map((star) {
                    final count = breakdown[star] ?? 0;
                    final pct = total == 0 ? 0.0 : count / total;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Text('$star', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 4),
                          const Icon(Icons.star_rounded, size: 12, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: pct,
                                minHeight: 7,
                                backgroundColor: AppColors.borderOf(context),
                                color: const Color(0xFFF59E0B),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$count',
                            style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondaryOf(context)),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (widget.onRateDoctor != null) ...[
          ElevatedButton.icon(
            onPressed: widget.onRateDoctor,
            icon: const Icon(Icons.rate_review_rounded, size: 18),
            label: const Text('Write a Review & Rate Doctor'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.patientTeal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),
        ],
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ReviewSort.values.map((s) {
              final label = switch (s) {
                ReviewSort.top => 'Top',
                ReviewSort.newest => 'Newest',
              };
              final selected = widget.sort == s;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) => widget.onSort(s),
                  selectedColor: AppColors.patientTeal.withValues(alpha: 0.15),
                  checkmarkColor: AppColors.patientTeal,
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        ..._sorted.map((r) => _ReviewCard(
              review: r,
              liked: _likedReviewIds.contains(r.id),
              helpfulCount: _displayHelpfulCount(r),
              toggling: _loadingVotes || _togglingReviewIds.contains(r.id),
              onToggleLike: () => unawaited(_toggleLike(r)),
              canEdit: r.canBeEditedBy(PatientSession.loggedInPatientId),
              onEdit: () => widget.onEditReview(r),
            )),
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.review,
    required this.liked,
    required this.helpfulCount,
    required this.toggling,
    required this.onToggleLike,
    this.canEdit = false,
    this.onEdit,
  });

  final PatientDoctorReview review;
  final bool liked;
  final int helpfulCount;
  final bool toggling;
  final VoidCallback onToggleLike;
  final bool canEdit;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBgOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(review.maskedName, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(
                DateFormat('dd MMM yyyy').format(review.date),
                style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondaryOf(context)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: List.generate(5, (i) {
              return Icon(
                i < review.rating ? Icons.star : Icons.star_border,
                size: 14,
                color: const Color(0xFFF59E0B),
              );
            }),
          ),
          const SizedBox(height: 8),
          Text(review.text, style: GoogleFonts.inter(fontSize: 14, height: 1.4)),
          const SizedBox(height: 10),
          Row(
            children: [
              InkWell(
                onTap: toggling ? null : onToggleLike,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        liked ? Icons.thumb_up : Icons.thumb_up_outlined,
                        size: 18,
                        color: liked ? AppColors.patientTeal : AppColors.textSecondaryOf(context),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        helpfulCount > 0 ? '$helpfulCount' : 'Like',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: liked ? AppColors.patientTeal : AppColors.textSecondaryOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (canEdit && onEdit != null) ...[
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.patientTeal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ],
          ),
          if (review.doctorReply != null) ...[
            const SizedBox(height: 8),
            Container(
              margin: const EdgeInsets.only(left: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceOf(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.borderOf(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Doctor reply', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.patientTeal)),
                  const SizedBox(height: 4),
                  Text(review.doctorReply!, style: GoogleFonts.inter(fontSize: 13)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LocationTab extends StatelessWidget {
  const _LocationTab({required this.doctor});

  final DoctorProfileDetail doctor;

  @override
  Widget build(BuildContext context) {
    return patientDoctorTabList(
      context,
      pageKey: 'location',
      scrollable: false,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            height: 160,
            color: AppColors.cardBgOf(context),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.map_outlined, size: 40, color: AppColors.textSecondaryOf(context).withValues(alpha: 0.5)),
                const SizedBox(height: 8),
                Text(
                  doctor.area.trim().isEmpty ? 'Location' : doctor.area,
                  style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
        if (doctor.mapsUrl.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => ExternalLauncher.openUrl(doctor.mapsUrl),
              icon: const Icon(Icons.directions_rounded, size: 18),
              label: const Text('Get directions'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.patientTeal,
                side: const BorderSide(color: AppColors.patientTeal),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        PatientDoctorSectionTitle(doctor.clinicName.isNotEmpty ? doctor.clinicName : 'Clinic'),
        Text(
          doctor.address.trim().isEmpty ? 'Address not added yet.' : doctor.address,
          style: GoogleFonts.inter(fontSize: 14, height: 1.45),
        ),
        if (doctor.landmark.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          PatientDoctorMetaRow(icon: Icons.place_outlined, text: 'Landmark: ${doctor.landmark}'),
        ],
        if (cleanProfileLabels(doctor.nearbyLandmarks).isNotEmpty) ...[
          const SizedBox(height: 20),
          const PatientDoctorSectionTitle('Nearby landmarks'),
          ...cleanProfileLabels(doctor.nearbyLandmarks).map((l) => PatientDoctorBulletItem(l)),
        ],
      ],
    );
  }
}

class _ClinicTimingsTable extends StatelessWidget {
  const _ClinicTimingsTable({required this.timings});

  final List<ClinicTiming> timings;

  static bool _isToday(String day) {
    final now = DateFormat('EEEE').format(DateTime.now());
    return day.toLowerCase().startsWith(now.toLowerCase().substring(0, 3));
  }

  @override
  Widget build(BuildContext context) {
    if (timings.isEmpty) {
      return Text(
        'Timings not added yet.',
        style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondaryOf(context)),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderOf(context)),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: timings.map((t) {
          final today = _isToday(t.day);
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: today ? AppColors.patientTeal.withValues(alpha: 0.06) : null,
              border: Border(bottom: BorderSide(color: AppColors.borderOf(context).withValues(alpha: 0.6))),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Text(
                        t.day,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: today ? AppColors.patientTeal : AppColors.textPrimaryOf(context),
                        ),
                      ),
                      if (today)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.patientTeal,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Today',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.surfaceOf(context),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    t.hours,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppColors.textSecondaryOf(context),
                      fontWeight: today ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
