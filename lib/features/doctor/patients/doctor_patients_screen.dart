import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/data/shared_appointments_store.dart';
import '../../../core/layout/responsive_layout.dart';
import '../../../core/session/doctor_session.dart';
import '../../../core/theme/app_colors.dart';
import 'data/doctor_patients_service.dart';
import 'package:medibond/features/patient/models/patient_models.dart';
import 'package:medibond/features/shared/screens/patient_profile_screen.dart';
import '../widgets/doctor_screen_title_bar.dart';
import 'widgets/invite_patient_sheet.dart';
import 'widgets/patient_filters_bar.dart';
import 'widgets/patient_list_card.dart';
import 'widgets/walkin_patient_sheet.dart';
import '../../../core/theme/app_typography.dart';

class DoctorPatientsScreen extends StatefulWidget {
  const DoctorPatientsScreen({super.key});

  @override
  State<DoctorPatientsScreen> createState() => _DoctorPatientsScreenState();
}

class _DoctorPatientsScreenState extends State<DoctorPatientsScreen> {
  final _searchController = TextEditingController();
  final _store = SharedAppointmentsStore.instance;
  PatientFilter _filter = PatientFilter.all;
  PatientSort _sort = PatientSort.lastVisit;
  bool _loading = true;
  bool _fabMenuOpen = false;

  static const _contentMaxWidth = 960.0;

  @override
  void initState() {
    super.initState();
    unawaited(_ensureLoaded());
  }

  Future<void> _ensureLoaded() async {
    await DoctorPatientsService.refreshOnTabOpen();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<DoctorPatientSummary> get _filtered {
    var list = DoctorPatientsService.summariesForDoctor(DoctorSession.loggedInDoctorId);

    final q = _searchController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((p) {
        return p.name.toLowerCase().contains(q) || p.mobile.contains(q);
      }).toList();
    }

    list = list.where((p) {
      return switch (_filter) {
        PatientFilter.all => true,
        PatientFilter.newPatient => p.isNew,
        PatientFilter.followUp => p.isFollowUp,
        PatientFilter.returning => !p.isNew,
        PatientFilter.dueForVisit => false,
        PatientFilter.abnormalLabs => false,
      };
    }).toList();

    list.sort((a, b) {
      return switch (_sort) {
        PatientSort.lastVisit => b.lastVisitDate.compareTo(a.lastVisitDate),
        PatientSort.name => a.name.compareTo(b.name),
        PatientSort.appointmentCount => b.totalVisits.compareTo(a.totalVisits),
      };
    });

    return list;
  }

  Future<void> _openWalkInSheet() async {
    await WalkInPatientSheet.show(context);
  }

  void _closeFabMenu() {
    if (_fabMenuOpen) setState(() => _fabMenuOpen = false);
  }

  Future<void> _onAddWalkIn() async {
    _closeFabMenu();
    await _openWalkInSheet();
  }

  Future<void> _onInviteViaLink() async {
    _closeFabMenu();
    await InvitePatientSheet.show(context);
  }

  void _openProfile(DoctorPatientSummary patient) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PatientProfileScreen(isDoctorView: true, patientId: patient.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = !ResponsiveLayout.isCompact(context);
    final horizontalPadding = wide ? 24.0 : 16.0;
    final fabBottom = wide ? 16.0 : 80.0;
    final fabClearance = _fabMenuOpen ? 200.0 : 72.0;

    return ColoredBox(
      color: wide ? AppColors.cardBgOf(context) : AppColors.surfaceOf(context),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_fabMenuOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeFabMenu,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
              ),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DoctorScreenTitleBar(title: 'Patients'),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: wide ? _contentMaxWidth : double.infinity,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PatientFiltersBar(
                          searchController: _searchController,
                          filter: _filter,
                          sort: _sort,
                          isLoading: _loading,
                          onSearchChanged: () => setState(() {}),
                          onFilterChanged: (f) => setState(() => _filter = f),
                          onSortChanged: (s) => setState(() => _sort = s),
                          onAddWalkIn: wide ? _onAddWalkIn : null,
                          onInviteViaLink: wide ? _onInviteViaLink : null,
                        ),
                        Expanded(
                          child: _loading
                              ? const Center(
                                  child: CircularProgressIndicator(color: AppColors.doctorBlue),
                                )
                              : ListenableBuilder(
                                  listenable: _store,
                                  builder: (context, _) {
                                    final patients = _filtered;
                                    if (patients.isEmpty) {
                                      return _EmptyPatientsState();
                                    }
                                    return RefreshIndicator(
                                      onRefresh: _ensureLoaded,
                                      child: ListView.builder(
                                        padding: EdgeInsets.fromLTRB(
                                          horizontalPadding,
                                          12,
                                          horizontalPadding,
                                          wide ? 20 : fabClearance + fabBottom,
                                        ),
                                        itemCount: patients.length,
                                        itemBuilder: (context, index) {
                                          final p = patients[index];
                                          return PatientListCard(
                                            patient: p,
                                            onViewProfile: () => _openProfile(p),
                                          );
                                        },
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (!wide)
            Positioned(
              bottom: fabBottom,
              right: 16,
              child: _PatientsFabSpeedDial(
                isOpen: _fabMenuOpen,
                isLoading: _loading,
                onToggle: () => setState(() => _fabMenuOpen = !_fabMenuOpen),
                onAddWalkIn: _onAddWalkIn,
                onInviteViaLink: _onInviteViaLink,
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyPatientsState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.doctorBlue.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.people_outline,
                size: 48,
                color: AppColors.doctorBlue.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No patients found',
              style: GoogleFonts.inter(
                fontSize: AppTypography.headlineSmall,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimaryOf(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Patients with appointments will appear here.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: AppTypography.bodyMedium,
                color: AppColors.textSecondaryOf(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientsFabSpeedDial extends StatelessWidget {
  const _PatientsFabSpeedDial({
    required this.isOpen,
    required this.isLoading,
    required this.onToggle,
    required this.onAddWalkIn,
    required this.onInviteViaLink,
  });

  final bool isOpen;
  final bool isLoading;
  final VoidCallback onToggle;
  final VoidCallback onAddWalkIn;
  final VoidCallback onInviteViaLink;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (isOpen) ...[
          _SpeedDialOption(
            label: 'Invite via Link',
            icon: Icons.link,
            onTap: onInviteViaLink,
          ),
          const SizedBox(height: 12),
          _SpeedDialOption(
            label: 'Add Walk-in',
            icon: Icons.person_add_outlined,
            onTap: isLoading ? null : onAddWalkIn,
          ),
          const SizedBox(height: 12),
        ],
        FloatingActionButton(
          onPressed: isLoading ? null : onToggle,
          backgroundColor: AppColors.doctorBlue,
          foregroundColor: Colors.white,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              isOpen ? Icons.close : Icons.add,
              key: ValueKey<bool>(isOpen),
            ),
          ),
        ),
      ],
    );
  }
}

class _SpeedDialOption extends StatelessWidget {
  const _SpeedDialOption({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceOf(context),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: AppTypography.bodySmall,
                  fontWeight: FontWeight.w600,
                  color: enabled ? AppColors.textPrimaryOf(context) : AppColors.textSecondaryOf(context),
                ),
              ),
            ),
            const SizedBox(width: 12),
            FloatingActionButton.small(
              heroTag: label,
              onPressed: onTap,
              backgroundColor: enabled ? AppColors.surfaceOf(context) : AppColors.textSecondaryOf(context).withValues(alpha: 0.2),
              foregroundColor: enabled ? AppColors.doctorBlue : AppColors.textSecondaryOf(context),
              elevation: 2,
              child: Icon(icon),
            ),
          ],
        ),
      ),
    );
  }
}
