import '../../../../core/notifications/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/session/doctor_session.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../patient/data/registered_doctors_store.dart';
import 'package:medibond/features/patient/models/patient_models.dart';
import '../models/clinical_models.dart';
import '../refer_patient_service.dart';
import '../../../../core/theme/app_typography.dart';

class ReferSpecialistDialog extends StatefulWidget {
  const ReferSpecialistDialog({
    super.key,
    required this.patient,
    this.initialReferrals = const [],
    this.onReferralsChanged,
  });

  final PatientClinicalContext patient;
  final List<ReferralEntry> initialReferrals;
  final ValueChanged<List<ReferralEntry>>? onReferralsChanged;

  static Future<void> show(
    BuildContext context, {
    required PatientClinicalContext patient,
    List<ReferralEntry> initialReferrals = const [],
    ValueChanged<List<ReferralEntry>>? onReferralsChanged,
  }) {
    RegisteredDoctorsStore.instance.startListening();
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16))),
        child: ReferSpecialistDialog(
          patient: patient,
          initialReferrals: initialReferrals,
          onReferralsChanged: onReferralsChanged,
        ),
      ),
    );
  }

  @override
  State<ReferSpecialistDialog> createState() => _ReferSpecialistDialogState();
}

class _ReferSpecialistDialogState extends State<ReferSpecialistDialog> {
  final _searchController = TextEditingController();
  final _reasonController = TextEditingController();
  late List<ReferralEntry> _pendingReferrals;
  bool _sending = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _pendingReferrals = widget.initialReferrals
        .map(
          (r) => ReferralEntry(
            doctorId: r.doctorId,
            doctorName: r.doctorName,
            specialization: r.specialization,
            reason: r.reason,
            sent: r.sent,
          ),
        )
        .toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  String get _reason => _reasonController.text.trim();

  void _notifyChanged() {
    widget.onReferralsChanged?.call(_pendingReferrals);
  }

  void _removePending(int index) {
    setState(() => _pendingReferrals.removeAt(index));
    _notifyChanged();
  }

  Future<void> _sendReferral(DoctorListing specialist) async {
    if (_reason.isEmpty) {
      AppToast.info(context, 'Please enter a reason for the referral');
      return;
    }
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await ReferPatientService.sendReferral(
        patient: widget.patient,
        specialist: specialist,
        reason: _reason,
      );
      if (!mounted) return;
      setState(() {
        final existing =
            _pendingReferrals.indexWhere((r) => r.doctorId == specialist.id);
        if (existing >= 0) {
          _pendingReferrals[existing].sent = true;
          _pendingReferrals[existing].reason = _reason;
        } else {
          _pendingReferrals.add(
            ReferralEntry(
              doctorId: specialist.id,
              doctorName: specialist.name,
              specialization: specialist.specialization,
              reason: _reason,
              sent: true,
            ),
          );
        }
      });
      _notifyChanged();
    } catch (e) {
      if (mounted) {
        AppToast.info(context, 'Referral failed: $e');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _savePending() async {
    final unsent = _pendingReferrals.where((r) => !r.sent).toList();
    if (unsent.isEmpty) {
      AppToast.info(context, 'Add at least one doctor to save');
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final store = RegisteredDoctorsStore.instance;
      for (final entry in unsent) {
        final specialist = store.findById(entry.doctorId);
        if (specialist == null) continue;
        await ReferPatientService.sendReferral(
          patient: widget.patient,
          specialist: specialist,
          reason: entry.reason.isNotEmpty ? entry.reason : _reason,
        );
        entry.sent = true;
      }
      if (!mounted) return;
      _notifyChanged();
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        AppToast.info(context, 'Save failed: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selfId = DoctorSession.loggedInDoctorId;
    final query = _searchController.text.trim().toLowerCase();
    final unsentCount = _pendingReferrals.where((r) => !r.sent).length;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 420,
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person_add_alt_1_outlined,
                    color: AppColors.doctorBlue, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Refer to Specialist',
                    style: GoogleFonts.inter(
                        fontSize: AppTypography.headlineSmall,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Refer ${widget.patient.patientName} to a verified DoctorNect doctor',
              style: GoogleFonts.inter(
                  fontSize: AppTypography.labelMedium,
                  color: AppColors.textSecondaryOf(context)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Search doctor or specialization',
                prefixIcon: Icon(Icons.search, size: 20),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reasonController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason (Mandatory)',
                alignLabelWithHint: true,
              ),
            ),
            if (_pendingReferrals.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Added referrals',
                style: GoogleFonts.inter(
                    fontSize: AppTypography.labelMedium,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < _pendingReferrals.length; i++)
                    InputChip(
                      label: Text(
                        _pendingReferrals[i].displayTitle,
                        style: GoogleFonts.inter(
                            fontSize: AppTypography.labelSmall),
                      ),
                      deleteIcon: _pendingReferrals[i].sent
                          ? const Icon(Icons.check,
                              size: 14, color: Color(0xFF16A34A))
                          : const Icon(Icons.close, size: 14),
                      onDeleted: _pendingReferrals[i].sent
                          ? null
                          : () => _removePending(i),
                      backgroundColor: _pendingReferrals[i].sent
                          ? const Color(0xFF16A34A).withValues(alpha: 0.1)
                          : AppColors.doctorBlue.withValues(alpha: 0.08),
                    ),
                ],
              ),
            ],
            const Divider(height: 20),
            Flexible(
              child: ListenableBuilder(
                listenable: RegisteredDoctorsStore.instance,
                builder: (context, _) {
                  final list = RegisteredDoctorsStore.instance.verifiedDoctors
                      .where((d) => d.id != selfId)
                      .where((d) {
                    if (query.isEmpty) return true;
                    return d.name.toLowerCase().contains(query) ||
                        d.specialization.toLowerCase().contains(query);
                  }).toList();

                  if (list.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          query.isEmpty
                              ? 'No verified doctors available yet.'
                              : 'No doctors match "$query".',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                              color: AppColors.textSecondaryOf(context),
                              fontSize: AppTypography.bodySmall),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final doctor = list[i];
                      final sent = _pendingReferrals
                          .where((r) => r.doctorId == doctor.id)
                          .any((r) => r.sent);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor:
                                  AppColors.doctorBlue.withValues(alpha: 0.12),
                              child: Text(
                                doctor.name.isNotEmpty
                                    ? doctor.name[0].toUpperCase()
                                    : 'D',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.doctorBlue,
                                  fontSize: AppTypography.bodySmall,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Dr. ${doctor.name}',
                                    style: GoogleFonts.inter(
                                        fontSize: AppTypography.bodyMedium,
                                        fontWeight: FontWeight.w500),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    doctor.specialization,
                                    style: GoogleFonts.inter(
                                        fontSize: AppTypography.labelMedium,
                                        color:
                                            AppColors.textSecondaryOf(context)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: (_sending || _saving || sent)
                                  ? null
                                  : () => _sendReferral(doctor),
                              style: FilledButton.styleFrom(
                                backgroundColor: sent
                                    ? AppColors.textSecondaryOf(context)
                                        .withValues(alpha: 0.35)
                                    : const Color(0xFF16A34A),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor:
                                    AppColors.textSecondaryOf(context)
                                        .withValues(alpha: 0.35),
                                disabledForegroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                minimumSize: const Size(0, 32),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                textStyle: GoogleFonts.inter(
                                  fontSize: AppTypography.labelMedium,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              child: Text(sent ? 'Sent' : 'Refer'),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            if (unsentCount > 0) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _savePending,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save_outlined, size: 18),
                  label: Text(
                      _saving ? 'Saving…' : 'Save $unsentCount referral(s)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.doctorBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
