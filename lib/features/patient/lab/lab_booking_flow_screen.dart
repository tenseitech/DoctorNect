import '../../../core/firebase/firestore_service.dart';
import '../../../core/notifications/app_toast.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/notifications/patient_notification_emitter.dart';
import '../../../core/notifications/patient_activity_store.dart';
import '../../../core/session/patient_session.dart';
import '../../../core/theme/app_colors.dart';
import '../profile/data/patient_profile_mock.dart';
import '../data/patient_favorites_store.dart';
import '../records/data/patient_lab_booking_store.dart';
import '../profile/models/patient_profile_models.dart';
import 'lab_booking_confirmed_screen.dart';
import 'lab_city_filter.dart';
import 'models/lab_models.dart';
import 'utils/patient_selected_investigations_mapper.dart';
import 'package:medibond/features/shared/widgets/lab_page_layout.dart';
import 'widgets/lab_step_header.dart';
import '../../../core/theme/app_typography.dart';

class LabBookingFlowScreen extends StatefulWidget {
  const LabBookingFlowScreen({
    super.key,
    required this.tests,
    this.partnerLabs = const [],
    this.preselectedLab,
    this.lockSelectedLab = false,
    this.submitAsRequest = false,
    this.onBookingCompleted,
  }) : assert(tests.length > 0, 'At least one test is required');

  final List<LabTestItem> tests;
  final List<PartnerLab> partnerLabs;
  final PartnerLab? preselectedLab;
  final bool lockSelectedLab;
  final bool submitAsRequest;
  final VoidCallback? onBookingCompleted;

  @override
  State<LabBookingFlowScreen> createState() => _LabBookingFlowScreenState();
}

class _LabBookingFlowScreenState extends State<LabBookingFlowScreen> {
  static const _titles = ['Select patient', 'Collection type', 'Schedule', 'Review'];

  int _step = 0;
  late LabBookingDraft _draft;
  bool _loading = true;
  String? _loadError; // FIXED: surface catalog-load failures instead of an infinite spinner
  final _addressController = TextEditingController();

  List<PartnerLab> _myLabsPartnerList() {
    return PatientFavoritesStore.instance
        .visibleLabs()
        .map((lab) => lab.toPartnerLab())
        .toList(growable: false);
  }

  List<PartnerLab> _walkInLabOptions() {
    if (widget.preselectedLab != null) return [widget.preselectedLab!];
    if (widget.lockSelectedLab && widget.partnerLabs.isNotEmpty) return widget.partnerLabs;
    return _myLabsPartnerList();
  }

  @override
  void initState() {
    super.initState();
    _addressController.text = PatientProfileMock.profileAddress.fullLabel.isNotEmpty
        ? PatientProfileMock.profileAddress.fullLabel
        : PatientProfileMock.profileCity;
    unawaited(_initDraft());
  }

  Future<void> _initDraft() async {
    try {
      await FirestoreService.instance.labCatalog.fetchCatalog();
    } catch (_) {
      if (!mounted) return; // FIXED: mounted check after await
      setState(() {
        _loading = false; // FIXED: stop the spinner on failure
        _loadError = 'Could not load lab booking options. Please check your connection and try again.';
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _draft = LabBookingDraft(
        test: widget.tests.first,
        patientName: PatientProfileMock.profile.name.isNotEmpty
            ? PatientProfileMock.profile.name
            : PatientSession.loggedInPatientName,
        patientAge: PatientProfileMock.profile.age,
      );
      final today = DateTime.now();
      _draft.selectedDate = DateTime(today.year, today.month, today.day);
      if (widget.preselectedLab != null) {
        _draft.selectedLab = widget.preselectedLab;
      } else if (widget.partnerLabs.isNotEmpty && widget.lockSelectedLab) {
        _draft.selectedLab = widget.partnerLabs.first;
      } else {
        _draft.selectedLab = null;
      }
      _loading = false;
    });
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
    } else {
      Navigator.pop(context);
    }
  }

  void _next() {
    if (_step < 3) {
      setState(() => _step++);
    } else {
      _confirm();
    }
  }

  bool _isValidPatientAge(int age) => age > 0 && age <= 120;

  bool _selectedPatientsHaveValidAges() {
    final profile = PatientProfileMock.profile;
    if (_draft.bookingForSelf && !_isValidPatientAge(profile.age)) return false;

    for (final id in _draft.familyMemberIds) {
      final member = PatientProfileMock.familyMembers.firstWhere(
        (f) => f.id == id,
        orElse: () => FamilyProfileMember(
          id: id,
          name: 'Family member',
          relation: FamilyRelation.other,
          age: 0,
          gender: '',
          bloodGroup: '',
        ),
      );
      if (!_isValidPatientAge(member.age)) return false;
    }
    return true;
  }

  String _selfPatientLabel() {
    final profile = PatientProfileMock.profile;
    final name = profile.name.isNotEmpty ? profile.name : PatientSession.loggedInPatientName;
    if (_isValidPatientAge(profile.age)) return '$name (${profile.age}y)';
    return '$name (age not set)';
  }

  bool get _requiresLabSelection => widget.preselectedLab == null && !widget.lockSelectedLab;

  bool _hasSelectedWalkInLab() {
    if (_draft.selectedLab == null) return false;
    final options = _walkInLabOptions();
    if (options.isEmpty) return false;
    final key = LabCityFilter.partnerLabKey(_draft.selectedLab!);
    return options.any((lab) => LabCityFilter.partnerLabKey(lab) == key);
  }

  bool _canContinue() => switch (_step) {
        0 =>
          (_draft.bookingForSelf || _draft.familyMemberIds.isNotEmpty) &&
              _selectedPatientsHaveValidAges(),
        1 => switch (_draft.collectionType) {
            LabCollectionType.walkIn =>
              _requiresLabSelection ? _hasSelectedWalkInLab() : _draft.selectedLab != null,
            LabCollectionType.home =>
              _addressController.text.trim().isNotEmpty &&
                  (!_requiresLabSelection || _hasSelectedWalkInLab()),
          },
        2 =>
          _draft.selectedDate != null &&
              _draft.selectedSlotLabel != null &&
              !LabSlotTime.isInPast(_draft.selectedDate!, _draft.selectedSlotLabel!),
        3 => true,
        _ => false,
      };

  String _relationLabel(FamilyRelation relation) => switch (relation) {
        FamilyRelation.spouse => 'Spouse',
        FamilyRelation.child => 'Child',
        FamilyRelation.parent => 'Parent',
        FamilyRelation.sibling => 'Sibling',
        FamilyRelation.friend => 'Friend',
        FamilyRelation.other => 'Other',
      };

  List<({String name, int age, bool isSelf, String? familyMemberId})> _selectedPatients() {
    final patients = <({String name, int age, bool isSelf, String? familyMemberId})>[];
    final profile = PatientProfileMock.profile;

    if (_draft.bookingForSelf) {
      patients.add((
        name: profile.name.isNotEmpty ? profile.name : PatientSession.loggedInPatientName,
        age: profile.age,
        isSelf: true,
        familyMemberId: null,
      ));
    }

    for (final id in _draft.familyMemberIds) {
      final member = PatientProfileMock.familyMembers.firstWhere(
        (f) => f.id == id,
        orElse: () => FamilyProfileMember(
          id: id,
          name: 'Family member',
          relation: FamilyRelation.other,
          age: 0,
          gender: '',
          bloodGroup: '',
        ),
      );
      patients.add((
        name: member.name,
        age: member.age,
        isSelf: false,
        familyMemberId: member.id,
      ));
    }

    return patients;
  }

  String _selectedPatientLabel() {
    return _selectedPatients().map((p) => '${p.name} (${p.age}y)').join(', ');
  }

  Future<void> _confirm() async {
    final patientId = PatientSession.loggedInPatientId;
    if (patientId.isEmpty) {
      AppToast.info(context, 'Please sign in as a patient to book a lab test.');
      return;
    }

    final patients = _selectedPatients();
    if (patients.isEmpty) {
      AppToast.info(context, 'Select at least one patient to continue.');
      return;
    }

    if (!_selectedPatientsHaveValidAges()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please set a valid age in Profile (or for family members) before booking.'),
        ),
      );
      return;
    }

    _draft.address = _addressController.text.trim();
    final status = widget.submitAsRequest ? 'requested' : 'confirmed';
    var firstBookingId = '';
    var patientIndex = 0;
    final savedBookings = <LabBookingRecord>[];

    try {
      for (final patient in patients) {
        final bookingId = LabBookingRepository.newBookingId(suffix: patientIndex);
        if (patientIndex == 0) firstBookingId = bookingId;
        patientIndex++;

        final saved = await FirestoreService.instance.labBooking.save(
          patientId: patientId,
          tests: widget.tests,
          draft: LabBookingDraft(
            test: widget.tests.first,
            patientName: patient.name,
            patientAge: patient.age,
            bookingForSelf: patient.isSelf,
            collectionType: _draft.collectionType,
            selectedLab: _draft.selectedLab,
            address: _draft.address,
            selectedDate: _draft.selectedDate,
            selectedSlotLabel: _draft.selectedSlotLabel,
          ),
          bookingId: bookingId,
          status: status,
          familyMemberId: patient.familyMemberId,
        );
        savedBookings.add(saved);
      }
    } catch (_) {
      if (!mounted) return;
      AppToast.info(context, 'Could not confirm your lab booking. Please try again.');
      return;
    }

    for (final saved in savedBookings) {
      PatientLabBookingStore.instance.upsertBooking(saved);
    }
    await PatientLabBookingStore.instance.refreshForPatient(patientId, preferCache: false);

    final bookingSummary = PatientSelectedInvestigationsMapper.summaryLabel(widget.tests);
    final booking = ConfirmedLabBooking(
      bookingId: firstBookingId,
      testName: bookingSummary,
      date: _draft.selectedDate!,
      slotLabel: _draft.selectedSlotLabel!,
      isHomeCollection: _draft.collectionType == LabCollectionType.home,
      address: _addressController.text,
      awaitingLabApproval: widget.submitAsRequest,
      labName: _draft.selectedLab?.name,
    );
    PatientActivityStore.instance.lastLabBooking = booking;

    if (widget.submitAsRequest) {
      final labName = _draft.selectedLab?.name ?? 'Lab';
      PatientNotificationEmitter.notifyLabBookingRequestSent(
        labName: labName,
        testName: bookingSummary,
        date: _draft.selectedDate!,
        slotLabel: _draft.selectedSlotLabel!,
        bookingId: firstBookingId,
      );
    }

    widget.onBookingCompleted?.call();

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => LabBookingConfirmedScreen(booking: booking)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.cardBgOf(context),
        body: const Center(child: CircularProgressIndicator(color: AppColors.labPurple)),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        backgroundColor: AppColors.cardBgOf(context),
        appBar: LabPageLayout.appBar(
          context,
          title: 'Book Lab Test',
          onBack: () => Navigator.pop(context),
        ),
        body: LabPageBody(
          centerVertically: true,
          child: LabContentCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_loadError!, textAlign: TextAlign.center, style: GoogleFonts.inter()),
                const SizedBox(height: 16),
                LabPrimaryButton(
                  label: 'Retry',
                  onPressed: () {
                    setState(() {
                      _loading = true;
                      _loadError = null;
                    });
                    unawaited(_initDraft());
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: LabPageLayout.appBar(
        context,
        title: 'Book Lab Test',
        onBack: _back,
      ),
      body: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.paddingOf(context).bottom),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: LabPageLayout.contentWidth(context)),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: LabContentCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LabStepHeader(currentStep: _step, totalSteps: 4, title: _titles[_step]),
                          const SizedBox(height: 20),
                          if (_step == 0)
                            _PatientStep(
                              draft: _draft,
                              relationLabel: _relationLabel,
                              selfPatientLabel: _selfPatientLabel(),
                              showMissingAgeHint: !_selectedPatientsHaveValidAges(),
                              onUpdate: (d) => setState(() => _draft = d),
                            ),
                          if (_step == 1)
                            _CollectionStep(
                              draft: _draft,
                              partnerLabs: _walkInLabOptions(),
                              addressController: _addressController,
                              labPreselected: widget.preselectedLab != null || widget.lockSelectedLab,
                              requiresLabSelection: _requiresLabSelection,
                              onUpdate: (d) => setState(() => _draft = d),
                            ),
                          if (_step == 2)
                            _ScheduleStep(
                              draft: _draft,
                              onUpdate: (d) => setState(() => _draft = d),
                            ),
                          if (_step == 3)
                            _ReviewStep(
                              draft: _draft,
                              tests: widget.tests,
                              patientLabel: _selectedPatientLabel(),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                LabPrimaryButton(
                  label: _step == 3
                      ? (widget.submitAsRequest ? 'Send request' : 'Confirm Booking')
                      : 'Continue',
                  enabled: _canContinue(),
                  onPressed: _canContinue() ? _next : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PatientStep extends StatelessWidget {
  const _PatientStep({
    required this.draft,
    required this.relationLabel,
    required this.selfPatientLabel,
    required this.showMissingAgeHint,
    required this.onUpdate,
  });

  final LabBookingDraft draft;
  final String Function(FamilyRelation relation) relationLabel;
  final String selfPatientLabel;
  final bool showMissingAgeHint;
  final ValueChanged<LabBookingDraft> onUpdate;

  LabBookingDraft _copy({
    bool? bookingForSelf,
    List<String>? familyMemberIds,
  }) {
    return LabBookingDraft(
      test: draft.test,
      patientName: draft.patientName,
      patientAge: draft.patientAge,
      bookingForSelf: bookingForSelf ?? draft.bookingForSelf,
      familyMemberIds: familyMemberIds ?? draft.familyMemberIds,
      collectionType: draft.collectionType,
      selectedLab: draft.selectedLab,
      address: draft.address,
      selectedDate: draft.selectedDate,
      selectedSlotLabel: draft.selectedSlotLabel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final familyMembers = PatientProfileMock.familyMembers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          title: Text('Myself ($selfPatientLabel)'),
          value: draft.bookingForSelf,
          onChanged: (value) => onUpdate(_copy(bookingForSelf: value ?? false)),
          activeColor: AppColors.labPurple,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
        ),
        ...familyMembers.map((member) {
          final isSelected = draft.familyMemberIds.contains(member.id);
          final ageLabel = member.age > 0 ? '${member.age}y' : 'age not set';
          return CheckboxListTile(
            title: Text('${relationLabel(member.relation)} — ${member.name} ($ageLabel)'),
            value: isSelected,
            onChanged: (value) {
              final ids = List<String>.from(draft.familyMemberIds);
              if (value == true) {
                if (!ids.contains(member.id)) ids.add(member.id);
              } else {
                ids.remove(member.id);
              }
              onUpdate(_copy(familyMemberIds: ids));
            },
            activeColor: AppColors.labPurple,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          );
        }),
        if (showMissingAgeHint)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Age is required for lab bookings. Update your Profile or family member details before continuing.',
              style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.error, height: 1.4),
            ),
          ),
      ],
    );
  }
}

class _CollectionStep extends StatelessWidget {
  const _CollectionStep({
    required this.draft,
    required this.partnerLabs,
    required this.addressController,
    required this.onUpdate,
    this.labPreselected = false,
    this.requiresLabSelection = false,
  });

  final LabBookingDraft draft;
  final List<PartnerLab> partnerLabs;
  final TextEditingController addressController;
  final ValueChanged<LabBookingDraft> onUpdate;
  final bool labPreselected;
  final bool requiresLabSelection;

  Widget _lockedLabCard() {
    final lab = draft.selectedLab;
    if (lab == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.labPurple.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: AppColors.labPurple.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_hospital_outlined, color: AppColors.labPurple),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lab.name,
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                ),
                if (lab.area.trim().isNotEmpty)
                  Text(
                    lab.area,
                    style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TypeCard(
          title: 'Home Collection',
          subtitle: 'Phlebotomist visits your address',
          icon: Icons.home_outlined,
          selected: draft.collectionType == LabCollectionType.home,
          onTap: () => onUpdate(LabBookingDraft(
            test: draft.test,
            patientName: draft.patientName,
            patientAge: draft.patientAge,
            bookingForSelf: draft.bookingForSelf,
            familyMemberIds: draft.familyMemberIds,
            collectionType: LabCollectionType.home,
            selectedLab: draft.selectedLab,
            selectedDate: draft.selectedDate,
            selectedSlotLabel: draft.selectedSlotLabel,
          )),
        ),
        const SizedBox(height: 12),
        _TypeCard(
          title: 'Walk-in',
          subtitle: labPreselected && draft.selectedLab != null
              ? 'Visit ${draft.selectedLab!.name}'
              : 'Visit my lab',
          icon: Icons.local_hospital_outlined,
          selected: draft.collectionType == LabCollectionType.walkIn,
          onTap: () => onUpdate(LabBookingDraft(
            test: draft.test,
            patientName: draft.patientName,
            patientAge: draft.patientAge,
            bookingForSelf: draft.bookingForSelf,
            familyMemberIds: draft.familyMemberIds,
            collectionType: LabCollectionType.walkIn,
            selectedLab: labPreselected ? draft.selectedLab : null,
            selectedDate: draft.selectedDate,
            selectedSlotLabel: draft.selectedSlotLabel,
          )),
        ),
        if (draft.collectionType == LabCollectionType.home) ...[
          const SizedBox(height: 16),
          TextField(
            controller: addressController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Collection address'),
          ),
          if (requiresLabSelection) ...[
            const SizedBox(height: 16),
            Text(
              'Select lab',
              style: GoogleFonts.inter(fontSize: AppTypography.bodyMedium, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _labPicker(context),
          ],
        ] else if (labPreselected && draft.selectedLab != null) ...[
          const SizedBox(height: 16),
          _lockedLabCard(),
        ] else ...[
          const SizedBox(height: 16),
          Text(
            'Select lab',
            style: GoogleFonts.inter(fontSize: AppTypography.bodyMedium, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _labPicker(context),
        ],
      ],
    );
  }

  Widget _labPicker(BuildContext context) {
    if (partnerLabs.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardBgOf(context),
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          border: Border.all(color: AppColors.borderOf(context)),
        ),
        child: Text(
          'No labs in My labs yet. Add a lab from the Lab tab to continue.',
          style: GoogleFonts.inter(fontSize: AppTypography.bodySmall, color: AppColors.textSecondaryOf(context), height: 1.45),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RadioGroup<PartnerLab>(
          groupValue: draft.selectedLab,
          onChanged: (v) {
            if (v == null) return;
            onUpdate(LabBookingDraft(
              test: draft.test,
              patientName: draft.patientName,
              patientAge: draft.patientAge,
              bookingForSelf: draft.bookingForSelf,
              familyMemberIds: draft.familyMemberIds,
              collectionType: draft.collectionType,
              selectedLab: v,
              selectedDate: draft.selectedDate,
              selectedSlotLabel: draft.selectedSlotLabel,
            ));
          },
          child: Column(
            children: partnerLabs.map((l) {
              return RadioListTile<PartnerLab>(
                title: Text(l.name),
                subtitle: Text(l.area),
                value: l,
                activeColor: AppColors.labPurple,
              );
            }).toList(),
          ),
        ),
        if (requiresLabSelection && draft.selectedLab == null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Choose a lab to continue.',
              style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondary),
            ),
          ),
      ],
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.labPurple.withValues(alpha: 0.08) : AppColors.surfaceOf(context),
      borderRadius: BorderRadius.circular(AppConstants.cardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppConstants.cardRadius),
            border: Border.all(color: selected ? AppColors.labPurple : AppColors.borderOf(context), width: selected ? 2 : 1),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.labPurple),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                    Text(subtitle, style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context))),
                  ],
                ),
              ),
              if (selected) const Icon(Icons.check_circle, color: AppColors.labPurple),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScheduleStep extends StatelessWidget {
  const _ScheduleStep({
    required this.draft,
    required this.onUpdate,
  });

  final LabBookingDraft draft;
  final ValueChanged<LabBookingDraft> onUpdate;

  LabBookingDraft _copy({DateTime? date, String? slot, bool clearSlot = false}) => LabBookingDraft(
        test: draft.test,
        patientName: draft.patientName,
        patientAge: draft.patientAge,
        bookingForSelf: draft.bookingForSelf,
        familyMemberIds: draft.familyMemberIds,
        collectionType: draft.collectionType,
        selectedLab: draft.selectedLab,
        address: draft.address,
        selectedDate: date ?? draft.selectedDate,
        selectedSlotLabel: clearSlot ? null : (slot ?? draft.selectedSlotLabel),
      );

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastDay = DateTime(now.year, 12, 31);
    final initial = draft.selectedDate ?? today;
    final clampedInitial = initial.isBefore(today)
        ? today
        : initial.isAfter(lastDay)
            ? lastDay
            : initial;

    final picked = await showDatePicker(
      context: context,
      initialDate: clampedInitial,
      firstDate: today,
      lastDate: lastDay,
      helpText: 'Select collection date',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(primary: AppColors.labPurple),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;

    onUpdate(_copy(date: picked, clearSlot: true));
  }

  Future<void> _pickTime(BuildContext context) async {
    final now = DateTime.now();
    final date = draft.selectedDate ?? DateTime(now.year, now.month, now.day);
    var initial = LabSlotTime.parse(draft.selectedSlotLabel) ?? const TimeOfDay(hour: 9, minute: 0);

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      initialEntryMode: TimePickerEntryMode.dialOnly,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
        child: Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(primary: AppColors.labPurple),
          ),
          child: child!,
        ),
      ),
    );
    if (picked == null) return;

    final label = LabSlotTime.format(picked);
    if (LabSlotTime.isInPast(date, label)) {
      if (!context.mounted) return;
      AppToast.info(context, 'Please choose a future time for today.');
      return;
    }

    onUpdate(_copy(slot: label));
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final selectedDate = draft.selectedDate ?? DateTime(now.year, now.month, now.day);
    final timeLabel = draft.selectedSlotLabel;
    final timeInPast = timeLabel != null && LabSlotTime.isInPast(selectedDate, timeLabel);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Select date', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Material(
          color: AppColors.cardBgOf(context),
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          child: InkWell(
            onTap: () => _pickDate(context),
            borderRadius: BorderRadius.circular(AppConstants.cardRadius),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, color: AppColors.labPurple),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      DateFormat('EEE, dd MMM yyyy').format(selectedDate),
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodyLarge,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: AppColors.textSecondaryOf(context).withValues(alpha: 0.7)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('Select time', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Material(
          color: AppColors.cardBgOf(context),
          borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          child: InkWell(
            onTap: () => _pickTime(context),
            borderRadius: BorderRadius.circular(AppConstants.cardRadius),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              child: Row(
                children: [
                  const Icon(Icons.schedule, color: AppColors.labPurple),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      timeLabel ?? 'Tap to choose a time',
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodyLarge,
                        fontWeight: FontWeight.w600,
                        color: timeLabel == null ? AppColors.textSecondaryOf(context) : AppColors.textPrimaryOf(context),
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: AppColors.textSecondaryOf(context).withValues(alpha: 0.7)),
                ],
              ),
            ),
          ),
        ),
        if (timeInPast)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'This time has already passed. Please pick another time.',
              style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.error),
            ),
          ),
      ],
    );
  }
}

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    required this.draft,
    required this.tests,
    required this.patientLabel,
  });

  final LabBookingDraft draft;
  final List<LabTestItem> tests;
  final String patientLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.cardBgOf(context),
            borderRadius: BorderRadius.circular(AppConstants.cardRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tests.length == 1 ? 'Test' : '${tests.length} tests',
                style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.textSecondaryOf(context)),
              ),
              const SizedBox(height: 6),
              ...tests.map(
                (test) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(test.name, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 8),
              Text('Patient: $patientLabel', style: GoogleFonts.inter(fontSize: AppTypography.labelMedium)),
              Text(
                '${DateFormat('dd MMM yyyy').format(draft.selectedDate!)} · ${draft.selectedSlotLabel}',
                style: GoogleFonts.inter(fontSize: AppTypography.labelMedium),
              ),
              Text(
                draft.collectionType == LabCollectionType.home
                    ? 'Home collection'
                    : 'Walk-in · ${draft.selectedLab?.name}',
                style: GoogleFonts.inter(fontSize: AppTypography.labelMedium, color: AppColors.labPurple),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
