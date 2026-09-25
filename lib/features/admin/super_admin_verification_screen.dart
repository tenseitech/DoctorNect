import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/admin/super_admin_verification_service.dart';
import '../../core/auth/app_logout.dart';
import '../../core/auth/verification_lifecycle.dart';
import '../../core/enums/user_type.dart';
import '../../core/notifications/app_toast.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../widgets/theme_toggle_button.dart';

class SuperAdminVerificationScreen extends StatefulWidget {
  const SuperAdminVerificationScreen({super.key});

  @override
  State<SuperAdminVerificationScreen> createState() =>
      _SuperAdminVerificationScreenState();
}

class _SuperAdminVerificationScreenState
    extends State<SuperAdminVerificationScreen> {
  UserType? _selectedRoleFilter;
  VerificationStage? _selectedStageFilter;

  final _roleTabs = const [
    (null, 'All Roles', Icons.apps_rounded),
    (UserType.doctor, 'Doctors', Icons.medical_services_rounded),
    (UserType.medicalStore, 'Pharmacies', Icons.local_pharmacy_rounded),
    (UserType.lab, 'Labs', Icons.biotech_rounded),
    (UserType.ambulance, 'Ambulances', Icons.emergency_rounded),
  ];

  final _stageFilters = const [
    (null, 'All Statuses'),
    (VerificationStage.submittedForVerification, 'In Review'),
    (VerificationStage.registered, 'Incomplete'),
    (VerificationStage.revisionRequested, 'Revision Requested'),
    (VerificationStage.verified, 'Verified'),
    (VerificationStage.rejected, 'Rejected'),
  ];

  void _openReviewModal(
      BuildContext context, VerificationApplicant applicant) async {
    final roleDetails = await SuperAdminVerificationService.instance
        .fetchRoleDetails(applicant.role, applicant.profileId);
    if (!context.mounted) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ApplicantReviewSheet(
        applicant: applicant,
        roleDetails: roleDetails,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF4F46E5).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.admin_panel_settings_rounded,
                  color: Color(0xFF4F46E5), size: 22),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Super Admin Portal',
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.titleMedium,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Professional Account Verification',
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.labelSmall,
                    color: AppColors.textSecondaryOf(context),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          const ThemeToggleButton(),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Log out',
            onPressed: () => AppLogout.confirmAndSignOut(context),
          ),
        ],
        elevation: 0,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Role selection chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: _roleTabs.map((tab) {
                final isSelected = _selectedRoleFilter == tab.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    avatar: Icon(
                      tab.$3,
                      size: 16,
                      color: isSelected ? Colors.white : AppColors.textSecondaryOf(context),
                    ),
                    label: Text(tab.$2),
                    selected: isSelected,
                    selectedColor: const Color(0xFF4F46E5),
                    labelStyle: GoogleFonts.inter(
                      fontSize: AppTypography.labelMedium,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? Colors.white : AppColors.textPrimaryOf(context),
                    ),
                    onSelected: (_) =>
                        setState(() => _selectedRoleFilter = tab.$1),
                  ),
                );
              }).toList(),
            ),
          ),
          // Status filters
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Row(
              children: _stageFilters.map((sf) {
                final isSelected = _selectedStageFilter == sf.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(sf.$2),
                    selected: isSelected,
                    selectedColor: isDark
                        ? const Color(0xFF312E81)
                        : const Color(0xFFEEF2FF),
                    labelStyle: GoogleFonts.inter(
                      fontSize: AppTypography.labelSmall,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected
                          ? const Color(0xFF4F46E5)
                          : AppColors.textSecondaryOf(context),
                    ),
                    onSelected: (_) =>
                        setState(() => _selectedStageFilter = sf.$1),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<List<VerificationApplicant>>(
              stream: SuperAdminVerificationService.instance.streamApplicants(
                roleFilter: _selectedRoleFilter,
                stageFilter: _selectedStageFilter,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error loading applications: ${snapshot.error}'),
                  );
                }

                final applicants = snapshot.data ?? [];
                if (applicants.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inbox_outlined,
                              size: 56, color: AppColors.textSecondaryOf(context)),
                          const SizedBox(height: 16),
                          Text(
                            'No applications found',
                            style: GoogleFonts.inter(
                              fontSize: AppTypography.headlineSmall,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimaryOf(context),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Try selecting another role or status filter above.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: AppTypography.bodySmall,
                              color: AppColors.textSecondaryOf(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: applicants.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final app = applicants[i];
                    return _ApplicantCard(
                      applicant: app,
                      onReview: () => _openReviewModal(context, app),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ApplicantCard extends StatelessWidget {
  const _ApplicantCard({
    required this.applicant,
    required this.onReview,
  });

  final VerificationApplicant applicant;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final roleColor = switch (applicant.role) {
      UserType.doctor => AppColors.doctorBlue,
      UserType.medicalStore => AppColors.pharmacyGreen,
      UserType.lab => AppColors.labPurple,
      UserType.ambulance => const Color(0xFFDC2626),
      _ => const Color(0xFF4F46E5),
    };

    final roleIcon = switch (applicant.role) {
      UserType.doctor => Icons.medical_services_outlined,
      UserType.medicalStore => Icons.local_pharmacy_outlined,
      UserType.lab => Icons.biotech_outlined,
      UserType.ambulance => Icons.emergency_outlined,
      _ => Icons.person_outline,
    };

    final dateStr = applicant.submittedAt != null
        ? DateFormat('d MMM yyyy, h:mm a').format(applicant.submittedAt!)
        : (applicant.createdAt != null
            ? DateFormat('d MMM yyyy').format(applicant.createdAt!)
            : 'Recently');

    return Card(
      elevation: 0,
      color: AppColors.surfaceOf(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppColors.borderOf(context)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onReview,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: roleColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(roleIcon, color: roleColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          applicant.displayName,
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.titleMedium,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${applicant.role.name.toUpperCase()} • $dateStr',
                          style: GoogleFonts.inter(
                            fontSize: AppTypography.labelSmall,
                            color: AppColors.textSecondaryOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StatusChip(stage: applicant.verificationStatus),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.phone_outlined,
                      size: 14, color: AppColors.textSecondaryOf(context)),
                  const SizedBox(width: 4),
                  Text(
                    applicant.mobile.isNotEmpty ? applicant.mobile : 'No phone',
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.bodySmall,
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.badge_outlined,
                      size: 14, color: AppColors.textSecondaryOf(context)),
                  const SizedBox(width: 4),
                  Text(
                    'ID: ${applicant.profileId}',
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.bodySmall,
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                  const Spacer(),
                  FilledButton.tonal(
                    onPressed: onReview,
                    style: FilledButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    ),
                    child: const Text('Review'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.stage});

  final VerificationStage stage;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color text) = switch (stage) {
      VerificationStage.verified => (
          const Color(0xFFDCFCE7),
          const Color(0xFF15803D),
        ),
      VerificationStage.submittedForVerification => (
          const Color(0xFFDBEAFE),
          const Color(0xFF1D4ED8),
        ),
      VerificationStage.revisionRequested => (
          const Color(0xFFFEF3C7),
          const Color(0xFFB45309),
        ),
      VerificationStage.rejected => (
          const Color(0xFFFEE2E2),
          const Color(0xFFB91C1C),
        ),
      _ => (
          const Color(0xFFF1F5F9),
          const Color(0xFF475569),
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        stage.displayLabel,
        style: GoogleFonts.inter(
          fontSize: AppTypography.labelSmall,
          fontWeight: FontWeight.w600,
          color: text,
        ),
      ),
    );
  }
}

class _ApplicantReviewSheet extends StatefulWidget {
  const _ApplicantReviewSheet({
    required this.applicant,
    required this.roleDetails,
  });

  final VerificationApplicant applicant;
  final Map<String, dynamic> roleDetails;

  @override
  State<_ApplicantReviewSheet> createState() => _ApplicantReviewSheetState();
}

class _ApplicantReviewSheetState extends State<_ApplicantReviewSheet> {
  bool _acting = false;

  Future<void> _approve() async {
    setState(() => _acting = true);
    final ok = await SuperAdminVerificationService.instance.approveProfile(
      uid: widget.applicant.uid,
      role: widget.applicant.role,
      profileId: widget.applicant.profileId,
    );
    if (!mounted) return;
    setState(() => _acting = false);
    if (ok) {
      AppToast.info(context, 'Account approved successfully!');
      Navigator.pop(context);
    } else {
      AppToast.error(context, 'Failed to approve account.');
    }
  }

  Future<void> _promptReason({required bool isRevision}) async {
    final controller = TextEditingController();
    final actionName = isRevision ? 'Request Revision' : 'Reject Application';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(actionName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isRevision
                  ? 'Specify what corrections or additional documents the applicant must provide:'
                  : 'Specify the reason for rejection:',
              style: GoogleFonts.inter(fontSize: AppTypography.bodyMedium),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Enter reason here...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: isRevision
                  ? const Color(0xFFD97706)
                  : const Color(0xFFDC2626),
            ),
            child: Text(isRevision ? 'Send Revision Request' : 'Confirm Rejection'),
          ),
        ],
      ),
    );

    if (confirmed == true && controller.text.trim().isNotEmpty && mounted) {
      setState(() => _acting = true);
      final ok = isRevision
          ? await SuperAdminVerificationService.instance.requestRevision(
              uid: widget.applicant.uid,
              role: widget.applicant.role,
              profileId: widget.applicant.profileId,
              reason: controller.text.trim(),
            )
          : await SuperAdminVerificationService.instance.rejectProfile(
              uid: widget.applicant.uid,
              role: widget.applicant.role,
              profileId: widget.applicant.profileId,
              reason: controller.text.trim(),
            );
      if (!mounted) return;
      setState(() => _acting = false);
      if (ok) {
        AppToast.info(context, isRevision ? 'Revision requested.' : 'Application rejected.');
        Navigator.pop(context);
      } else {
        AppToast.error(context, 'Action failed. Please try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.applicant;
    final requirements =
        VerificationRequirementsConfig.requirementsForRole(app.role);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderOf(context),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              app.displayName,
                              style: GoogleFonts.inter(
                                fontSize: AppTypography.headlineMedium,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${app.role.name.toUpperCase()} • Mobile: ${app.mobile}',
                              style: GoogleFonts.inter(
                                fontSize: AppTypography.bodySmall,
                                color: AppColors.textSecondaryOf(context),
                              ),
                            ),
                            Text(
                              'Profile ID: ${app.profileId}',
                              style: GoogleFonts.inter(
                                fontSize: AppTypography.bodySmall,
                                color: AppColors.textSecondaryOf(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _StatusChip(stage: app.verificationStatus),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (app.rejectionReason != null &&
                      app.rejectionReason!.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Text(
                        'Existing Note/Reason: "${app.rejectionReason}"',
                        style: GoogleFonts.inter(
                          fontSize: AppTypography.bodySmall,
                          color: const Color(0xFF92400E),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Text(
                    'Verification Checklist & Credentials',
                    style: GoogleFonts.inter(
                      fontSize: AppTypography.titleMedium,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final req in requirements) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.cardBgOf(context),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.borderOf(context)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            req.isDocument
                                ? Icons.file_present_rounded
                                : Icons.fact_check_outlined,
                            size: 20,
                            color: const Color(0xFF4F46E5),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  req.label,
                                  style: GoogleFonts.inter(
                                    fontSize: AppTypography.bodyMedium,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  req.description,
                                  style: GoogleFonts.inter(
                                    fontSize: AppTypography.labelSmall,
                                    color: AppColors.textSecondaryOf(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            widget.roleDetails.containsKey(req.key)
                                ? '${widget.roleDetails[req.key]}'
                                : 'Submitted',
                            style: GoogleFonts.inter(
                              fontSize: AppTypography.bodySmall,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimaryOf(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _acting
                            ? null
                            : () => _promptReason(isRevision: false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFDC2626),
                          side: const BorderSide(color: Color(0xFFDC2626)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Reject'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _acting
                            ? null
                            : () => _promptReason(isRevision: true),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFD97706),
                          side: const BorderSide(color: Color(0xFFD97706)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Request Revision'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _acting ? null : _approve,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: _acting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Approve & Verify'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
