import '../../../core/firebase/firestore_service.dart';
import '../../../core/notifications/app_toast.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/data/shared_appointments_store.dart';
import '../../../core/notifications/doctor_notification_emitter.dart';
import '../../../core/notifications/patient_activity_store.dart';
import '../../../core/notifications/patient_notification_emitter.dart';
import '../../../core/firebase/firebase_error_messages.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/firebase/models/doctor_availability.dart';
import '../../../features/doctor/profile/data/doctor_profile_store.dart';
import '../data/registered_doctors_store.dart';
import '../models/patient_models.dart' hide DoctorAvailability;
import '../doctor_profile/models/doctor_profile_detail.dart';
import '../profile/data/patient_profile_mock.dart';
import '../profile/models/patient_profile_models.dart';
import '../profile/widgets/patient_profile_form_styles.dart';
import 'models/booking_models.dart';
import '../sharing/patient_sharing_utils.dart';
import 'utils/booking_flow_helpers.dart';
import 'widgets/add_family_member_sheet.dart';
import 'widgets/booking_confirmed_view.dart';
import 'widgets/booking_step_header.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/session/patient_session.dart';
import '../../../core/supabase/supabase_bootstrap.dart';
import '../../../core/supabase/supabase_patient_repository.dart';
import '../../../core/supabase/patient_write_guard.dart';

class BookingFlowScreen extends StatefulWidget {
  const BookingFlowScreen({
    super.key,
    required this.doctorId,
    this.rescheduleFromRecordId,
  });

  final String doctorId;

  /// When set, confirming booking reschedules this appointment instead of creating a new one.
  final String? rescheduleFromRecordId;

  @override
  State<BookingFlowScreen> createState() => _BookingFlowScreenState();
}

class _BookingFlowScreenState extends State<BookingFlowScreen> {
  static const _stepTitles = [
    'Select date & time',
    'Patient details',
    'Review & confirm',
  ];

  int _step = 0;
  late DoctorProfileDetail? _doctor;
  late BookingDraft _draft = BookingDraft(doctorId: '', doctorName: '');
  List<TimeSlot> _slots = [];
  bool _loadingDoctor = true;
  bool _loadingSlots = true;
  final Map<String, TextEditingController> _reasonControllers = {};
  List<FamilyMember> _familyMembers = [];
  ConfirmedBooking? _confirmed;
  DoctorAvailability _schedule = DoctorAvailability.defaults();
  final _availabilityRepo = FirestoreService.instance.doctorAvailability;
  final _slotShareReasonController = TextEditingController();

  TextEditingController _getController(String key) {
    if (!_reasonControllers.containsKey(key)) {
      _reasonControllers[key] = TextEditingController();
    }
    return _reasonControllers[key]!;
  }

  @override
  void initState() {
    super.initState();
    _familyMembers = _familyMembersFromProfile();
    PatientProfileMock.listenable.addListener(_onProfileChanged);
    unawaited(_loadDoctor());
  }

  void _onProfileChanged() {
    if (!mounted) return;
    setState(() => _familyMembers = _familyMembersFromProfile());
  }

  Future<void> _loadDoctor() async {
    try {
      var doctor = await FirestoreService.instance.doctorProfileDetail
          .fetch(widget.doctorId)
          .timeout(const Duration(seconds: 12));
      doctor ??= _doctorFromListing(
          RegisteredDoctorsStore.instance.findById(widget.doctorId));
      await _applyLoadedDoctor(doctor);
    } catch (_) {
      if (!mounted) return;
      await _applyLoadedDoctor(
        _doctorFromListing(
            RegisteredDoctorsStore.instance.findById(widget.doctorId)),
      );
    }
  }

  DoctorProfileDetail? _doctorFromListing(DoctorListing? listing) {
    if (listing == null) return null;
    return DoctorProfileDetail(
      id: listing.id,
      name: listing.name,
      specialization: listing.specialization,
      qualification: listing.qualification,
      experienceYears: listing.experienceYears,
      rating: listing.rating,
      reviewCount: listing.reviewCount,
      verified: listing.verified,
      languages: listing.languages,
      phone: 'Contact via clinic',
      about: 'Dr. ${listing.name} is a registered ${listing.specialization}.',
      specialities: [listing.specialization],
      services: const ['Consultation', 'Follow-up', 'Prescription'],
      timings: const [
        ClinicTiming(day: 'Schedule', hours: 'Select a date and time below')
      ],
      education: [
        EducationEntry(degree: listing.qualification, college: '—', year: 0),
      ],
      pastWorkplaces: const [],
      awards: const [],
      publications: const [],
      memberships: const [],
      reviews: const [],
      address: '${listing.clinicName}, ${listing.area}',
      landmark: '',
      mapsUrl:
          'https://maps.google.com/?q=${Uri.encodeComponent('${listing.clinicName} ${listing.area}')}',
      nearbyLandmarks: const [],
      clinicName: listing.clinicName,
      area: listing.area,
    );
  }

  Future<void> _applyLoadedDoctor(DoctorProfileDetail? doctor) async {
    if (!mounted) return;
    if (doctor == null) {
      setState(() {
        _doctor = null;
        _loadingDoctor = false;
        _loadingSlots = false;
      });
      return;
    }

    final today = DateTime.now();
    final firstDate = DateTime(today.year, today.month, today.day);
    DoctorAvailability schedule;
    try {
      schedule =
          await _availabilityRepo.fetch(widget.doctorId, preferCache: true) ??
              DoctorAvailability.defaults();
    } catch (_) {
      schedule = DoctorAvailability.defaults();
    }

    var selectedDate = firstDate;
    if (_availabilityRepo.isUnavailableDay(schedule, firstDate)) {
      for (var i = 0; i < 90; i++) {
        final candidate = firstDate.add(Duration(days: i));
        if (!_availabilityRepo.isUnavailableDay(schedule, candidate)) {
          selectedDate = candidate;
          break;
        }
      }
    }

    setState(() {
      _doctor = doctor;
      _loadingDoctor = false;
      _schedule = schedule;
      _draft = BookingDraft(
        doctorId: widget.doctorId,
        doctorName: doctor.name,
        selectedDate: selectedDate,
      );
    });
    await _loadSlotsForDate(selectedDate);
  }

  List<FamilyMember> _familyMembersFromProfile() {
    return PatientProfileMock.familyMembers
        .map(
          (f) => FamilyMember(
            id: f.id,
            name: f.name,
            age: f.age,
            relation: _relationLabel(f.relation),
            gender: f.gender,
          ),
        )
        .toList();
  }

  String _relationLabel(FamilyRelation relation) => switch (relation) {
        FamilyRelation.spouse => 'Spouse',
        FamilyRelation.child => 'Child',
        FamilyRelation.parent => 'Parent',
        FamilyRelation.sibling => 'Sibling',
        FamilyRelation.friend => 'Friend',
        FamilyRelation.other => 'Other',
      };

  Future<void> _loadSlotsForDate(DateTime date) async {
    setState(() => _loadingSlots = true);
    try {
      final slots = await _availabilityRepo.slotsForDate(
        doctorId: widget.doctorId,
        date: date,
      );
      if (!mounted) return;
      setState(() {
        _slots = slots;
        _loadingSlots = false;
        final selectedId = _draft.selectedSlotId;
        if (selectedId != null) {
          final stillValid =
              slots.any((s) => s.id == selectedId && s.isSelectable);
          if (!stillValid) {
            _draft = BookingDraft(
              doctorId: _draft.doctorId,
              doctorName: _draft.doctorName,
              selectedDate: _draft.selectedDate,
            );
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _slots = const [];
        _loadingSlots = false;
      });
    }
  }

  @override
  void dispose() {
    PatientProfileMock.listenable.removeListener(_onProfileChanged);
    _slotShareReasonController.dispose();
    for (final c in _reasonControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TimeSlot? get _selectedSlot {
    final id = _draft.selectedSlotId;
    if (id == null) return null;
    for (final slot in _slots) {
      if (slot.id == id) return slot;
    }
    return null;
  }

  int _existingSlotBookings() {
    final date = _draft.selectedDate;
    final label = _draft.selectedSlotLabel;
    if (date == null || label == null || label.isEmpty) return 0;
    return SharedAppointmentsStore.instance.bookingCountForSlot(
      widget.doctorId,
      date,
      label,
    );
  }

  String? _resolvedSlotShareReason() {
    return PatientSharingUtils.resolveSlotShareReason(
      existingSlotBookings: _existingSlotBookings(),
      type: _draft.slotShareReasonType,
      reasonText: _draft.slotShareReasonText,
    );
  }

  bool _slotStepValid() {
    final slot = _selectedSlot;
    return PatientSharingUtils.isSlotShareStepValid(
      slotSelectable: slot != null && slot.isSelectable,
      existingSlotBookings: _existingSlotBookings(),
      type: _draft.slotShareReasonType,
      reasonText: _draft.slotShareReasonText,
    );
  }

  bool _slotHasCapacityForPatients() {
    return PatientSharingUtils.hasSlotCapacityForPatients(
      existingSlotBookings: _existingSlotBookings(),
      patientCount: _patientNames().length,
    );
  }

  void _showBookingMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _next() {
    if (_step == 0) {
      if (!_slotStepValid()) {
        final slot = _selectedSlot;
        _showBookingMessage(
          slot != null && !slot.isSelectable
              ? 'This time has already passed. Please choose a later slot.'
              : _existingSlotBookings() >= 1
                  ? 'Select Emergency or Other and provide a reason to share this slot'
                  : 'Please select a time slot',
        );
        return;
      }
    } else if (_step == 1) {
      if (!_slotHasCapacityForPatients()) {
        _showBookingMessage(
          'This time slot allows maximum $kMaxPatientsPerTimeSlot patients. Choose another slot or fewer people.',
        );
        return;
      }
      if (!_draft.bookingForSelf && _draft.familyMemberIds.isEmpty) {
        _showBookingMessage(
            'Please select who you are booking for (Myself or a Family Member).');
        return;
      }
      if (_draft.bookingForSelf && _getController('self').text.trim().isEmpty) {
        _showBookingMessage('Please enter reason for visit for yourself.');
        return;
      }
      for (final id in _draft.familyMemberIds) {
        if (_getController(id).text.trim().isEmpty) {
          final member = _familyMembers.firstWhere(
            (m) => m.id == id,
            orElse: () => FamilyMember(
                id: id,
                name: 'Family Member',
                age: 0,
                relation: '',
                gender: ''),
          );
          _showBookingMessage(
              'Please enter reason for visit for ${member.name}.');
          return;
        }
      }
    }

    if (_step < 2) {
      setState(() => _step++);
      if (_step == 1 && _draft.selectedDate != null) {
        unawaited(_loadSlotsForDate(_draft.selectedDate!));
      }
    } else {
      _confirmPay();
    }
  }

  void _back() {
    if (_step > 0) {
      final previousStep = _step - 1;
      setState(() => _step = previousStep);
      if (previousStep == 0 && _draft.selectedDate != null) {
        unawaited(_loadSlotsForDate(_draft.selectedDate!));
      }
    } else {
      Navigator.pop(context);
    }
  }

  bool _canContinue() {
    final selfReasonOk =
        !_draft.bookingForSelf || _getController('self').text.trim().isNotEmpty;
    bool familyReasonsOk = true;
    for (final id in _draft.familyMemberIds) {
      if (_getController(id).text.trim().isEmpty) {
        familyReasonsOk = false;
        break;
      }
    }
    final reasonsOk = selfReasonOk && familyReasonsOk;

    return switch (_step) {
      0 => _slotStepValid(),
      1 => (_draft.bookingForSelf || _draft.familyMemberIds.isNotEmpty) &&
          _slotHasCapacityForPatients() &&
          reasonsOk,
      2 => _slotHasCapacityForPatients(),
      _ => false,
    };
  }

  List<String> _patientNames() {
    final names = <String>[];
    if (_draft.bookingForSelf) {
      names.add(PatientProfileMock.profile.name.isNotEmpty
          ? PatientProfileMock.profile.name
          : 'Patient');
    }
    for (final id in _draft.familyMemberIds) {
      final f = _familyMembers.firstWhere((m) => m.id == id,
          orElse: () => FamilyMember(
              id: id,
              name: 'Family Member',
              age: 0,
              relation: '',
              gender: 'Female'));
      names.add(f.name);
    }
    return names;
  }

  Future<void> _addFamilyMember() async {
    final added = await showDialog<FamilyMember>(
      context: context,
      builder: (_) => const AddFamilyMemberSheet(),
    );
    if (added == null || !mounted) return;
    setState(() {
      _familyMembers = [..._familyMembers, added];
      _draft = BookingDraft(
        doctorId: _draft.doctorId,
        doctorName: _draft.doctorName,
        selectedDate: _draft.selectedDate,
        selectedSlotId: _draft.selectedSlotId,
        selectedSlotLabel: _draft.selectedSlotLabel,
        bookingForSelf: _draft.bookingForSelf,
        familyMemberIds: [..._draft.familyMemberIds, added.id],
        slotShareReasonType: _draft.slotShareReasonType,
        slotShareReasonText: _draft.slotShareReasonText,
      );
    });

    // FIXED: persist the new family member (was previously kept in local state only).
    try {
      await PatientProfileMock.addFamilyMember(
        FamilyProfileMember(
          id: added.id,
          name: added.name,
          relation: FamilyRelation.values.firstWhere(
            (r) => r.name.toLowerCase() == added.relation.trim().toLowerCase(),
            orElse: () =>
                FamilyRelation.other, // FIXED: null-safe relation mapping
          ),
          age: added.age,
          gender: added.gender,
          bloodGroup: '',
        ),
      );
    } catch (_) {
      if (!mounted) return; // FIXED: mounted check after await
      AppToast.info(context,
          'Family member added for this booking, but could not be saved to your profile.');
    }
  }

  Future<void> _confirmPay() async {
    final patientNames = _patientNames();
    final combinedName = patientNames.join(', ');
    final profile = PatientProfileMock.profile;
    final listing = RegisteredDoctorsStore.instance.findById(widget.doctorId);
    final clinicAddress =
        _doctor?.address ?? 'Clinic address in appointment details';
    final slotLabel = _draft.selectedSlotLabel ?? '';
    final date = _draft.selectedDate!;
    final store = SharedAppointmentsStore.instance;
    final slotShareReason = _resolvedSlotShareReason();

    final selectedSlot = _selectedSlot;
    if (selectedSlot == null || !selectedSlot.isSelectable) {
      _showBookingMessage(
        'This time has already passed. Please choose a later slot.',
      );
      setState(() => _step = 0);
      if (_draft.selectedDate != null) {
        unawaited(_loadSlotsForDate(_draft.selectedDate!));
      }
      return;
    }

    if (!_slotHasCapacityForPatients()) {
      _showBookingMessage(
        'This time slot is full. Maximum $kMaxPatientsPerTimeSlot patients allowed at the same time.',
      );
      return;
    }

    if (widget.rescheduleFromRecordId == null &&
        _existingSlotBookings() >= 1 &&
        (slotShareReason == null || slotShareReason.isEmpty)) {
      _showBookingMessage(
          'Please provide a reason for sharing this time slot.');
      return;
    }

    if (widget.rescheduleFromRecordId != null) {
      final old = store.findRecordById(widget.rescheduleFromRecordId!);
      final oldLabel = old != null
          ? '${DateFormat('dd MMM').format(old.dateTime)} · ${old.slotLabel}'
          : '';
      final newLabel = '${DateFormat('dd MMM').format(date)} · $slotLabel';
      final sameDay = old != null &&
          old.dateTime.year == date.year &&
          old.dateTime.month == date.month &&
          old.dateTime.day == date.day;
      final newToken = sameDay
          ? old.tokenNumber
          : store.nextTokenNumberForDoctorOnDate(widget.doctorId, date);

      DateTime newSlotDateTime = date;
      final timeOfDay = parseSlotTimeLabel(slotLabel);
      if (timeOfDay != null) {
        newSlotDateTime = DateTime(
          date.year,
          date.month,
          date.day,
          timeOfDay.hour,
          timeOfDay.minute,
        );
      }

      try {
        if (SupabaseBootstrap.isReady && old?.appointmentId != null) {
          await SupabasePatientRepository.instance.bookAppointment(
            context: context,
            appointmentId: old!.appointmentId,
            doctorId: widget.doctorId,
            patientId: old.patientId ??
                (PatientSession.loggedInPatientId.isNotEmpty
                    ? PatientSession.loggedInPatientId
                    : 'pat-default'),
            doctorName: _draft.doctorName,
            specialization: listing?.specialization ??
                _doctor?.specialization ??
                'General Physician',
            patientName: combinedName,
            patientAge: profile.age,
            patientGender:
                BookingFlowHelpers.resolvePatientGender(profile.gender) ??
                    'Other',
            dateTime: newSlotDateTime,
            slotLabel: slotLabel,
            visitType: 'followUp',
            tokenNumber: newToken,
            clinicName: _doctor?.clinicName,
            clinicAddress: clinicAddress,
          );
        }
        await store.reschedulePatient(
          recordId: widget.rescheduleFromRecordId!,
          newDate: date,
          newSlotLabel: slotLabel,
          newToken: newToken,
        );
      } on PatientMaintenanceException catch (_) {
        // Friendly maintenance sheet already displayed by PatientWriteGuard
        return;
      } catch (e) {
        if (!mounted) return;
        _showBookingMessage(
          describeUserFacingError(e,
              fallback:
                  "Couldn't reschedule this appointment. Please check your connection and try again."),
        );
        return;
      }

      DoctorNotificationEmitter.notifyAppointmentRescheduledByPatient(
        patientName: combinedName,
        oldLabel: oldLabel,
        newLabel: newLabel,
        appointmentId: old?.appointmentId,
      );
      PatientNotificationEmitter.notifyDoctorRescheduled(
        doctorName: _draft.doctorName,
        oldDateTime: oldLabel,
        newDateTime: newLabel,
      );

      setState(() {
        _confirmed = ConfirmedBooking(
          appointmentId: old?.appointmentId ?? '',
          tokenNumber: newToken,
          doctorName: _draft.doctorName,
          date: date,
          slotLabel: slotLabel,
          patientName: combinedName,
          clinicAddress: _doctor?.address,
        );
        _step = 3;
      });
      return;
    }

    bool allConfirmed = true;
    String? firstAppointmentId;
    int? firstToken;

    if (_draft.bookingForSelf &&
        BookingFlowHelpers.resolvePatientGender(profile.gender) == null) {
      _showBookingMessage('Please set your gender in Profile before booking.');
      return;
    }
    for (final id in _draft.familyMemberIds) {
      final f = _familyMembers.firstWhere(
        (m) => m.id == id,
        orElse: () => FamilyMember(
            id: id, name: 'Family Member', age: 0, relation: '', gender: ''),
      );
      if (BookingFlowHelpers.resolvePatientGender(f.gender) == null) {
        _showBookingMessage(
            'Please set a valid gender for ${f.name} before booking.');
        return;
      }
    }

    Future<void> processBooking(
      String pName,
      int pAge,
      String pGender,
      String pReason, {
      String? bookedBy,
      String? patientRelation,
    }) async {
      final appointmentId = BookingFlowHelpers.newAppointmentId();
      firstAppointmentId ??= appointmentId;
      final token = store.nextTokenNumberForDoctorOnDate(widget.doctorId, date);
      firstToken ??= token;

      DateTime slotDateTime = date;
      final timeOfDay = parseSlotTimeLabel(slotLabel);
      if (timeOfDay != null) {
        slotDateTime = DateTime(
          date.year,
          date.month,
          date.day,
          timeOfDay.hour,
          timeOfDay.minute,
        );
      }

      // 1. PRIMARY WRITE: Supabase PostgreSQL (Patient Module Staged Cutover)
      // Guarded by PatientWriteGuard for maintenance kill-switch & 42501 defense
      if (SupabaseBootstrap.isReady) {
        await SupabasePatientRepository.instance.bookAppointment(
          context: context,
          appointmentId: appointmentId,
          doctorId: widget.doctorId,
          patientId: PatientSession.loggedInPatientId.isNotEmpty
              ? PatientSession.loggedInPatientId
              : 'pat-default',
          doctorName: _draft.doctorName,
          specialization: listing?.specialization ??
              _doctor?.specialization ??
              'General Physician',
          patientName: pName,
          patientAge: pAge,
          patientGender: pGender,
          dateTime: slotDateTime,
          slotLabel: slotLabel,
          visitType: 'newVisit',
          tokenNumber: token,
          clinicName: _doctor?.clinicName,
          clinicAddress: clinicAddress,
        );
      }

      // 2. Synchronize local store for UI responsiveness
      final confirmed = await store.addBooking(
        doctorId: widget.doctorId,
        doctorName: _draft.doctorName,
        specialization: listing?.specialization ??
            _doctor?.specialization ??
            'General Physician',
        date: date,
        slotLabel: slotLabel,
        appointmentId: appointmentId,
        tokenNumber: token,
        patientName: pName,
        patientAge: pAge,
        patientGender: pGender,
        clinicName: _doctor?.clinicName,
        clinicAddress: clinicAddress,
        mapsUrl: _doctor?.mapsUrl,
        reasonForVisit: pReason.trim().isEmpty ? null : pReason.trim(),
        bookedByName: bookedBy,
        patientRelation: patientRelation,
        slotShareReason: slotShareReason,
      );
      if (!confirmed) allConfirmed = false;
    }

    final mainPatientName = PatientProfileMock.profile.name.isNotEmpty
        ? PatientProfileMock.profile.name
        : 'Patient';

    try {
      if (_draft.bookingForSelf) {
        final hasFamily = _draft.familyMemberIds.isNotEmpty;
        await processBooking(
          mainPatientName,
          profile.age,
          BookingFlowHelpers.resolvePatientGender(profile.gender)!,
          _reasonControllers['self']?.text ?? '',
          bookedBy: hasFamily ? mainPatientName : null,
          patientRelation: hasFamily ? 'Self' : null,
        );
      }

      for (final id in _draft.familyMemberIds) {
        final f = _familyMembers.firstWhere(
          (m) => m.id == id,
          orElse: () => FamilyMember(
              id: id, name: 'Family Member', age: 0, relation: '', gender: ''),
        );
        await processBooking(
          f.name,
          f.age,
          BookingFlowHelpers.resolvePatientGender(f.gender)!,
          _reasonControllers[id]?.text ?? '',
          bookedBy: mainPatientName,
          patientRelation: f.relation,
        );
      }
    } on PatientMaintenanceException catch (_) {
      // PatientWriteGuard has already presented the friendly maintenance bottom sheet
      return;
    } catch (e) {
      if (!mounted) return;
      _showBookingMessage(
        describeUserFacingError(e,
            fallback:
                "Couldn't confirm this booking. Please check your connection and try again."),
      );
      return;
    }

    final displayToken = firstToken ?? 1;

    if (allConfirmed) {
      PatientNotificationEmitter.notifyBookingConfirmed(
        doctorName: _draft.doctorName,
        date: date,
        timeLabel: slotLabel,
        token: displayToken,
        locationOrLink: clinicAddress,
        appointmentId: firstAppointmentId ?? '',
      );
    } else {
      PatientNotificationEmitter.notifyBookingRequestSent(
        doctorName: _draft.doctorName,
        date: date,
        timeLabel: slotLabel,
        appointmentId: firstAppointmentId ?? '',
      );
    }

    PatientActivityStore.instance
      ..lastBookedDoctorName = _draft.doctorName
      ..lastBookedAppointmentAt = date
      ..lastBookedSlotLabel = slotLabel
      ..lastBookedClinicAddress = clinicAddress
      ..lastBookedToken = displayToken
      ..lastClinicBookingAt = DateTime.now();

    setState(() {
      _confirmed = ConfirmedBooking(
        appointmentId: firstAppointmentId ?? '',
        tokenNumber: displayToken,
        doctorName: _draft.doctorName,
        date: date,
        slotLabel: slotLabel,
        patientName: combinedName,
        clinicAddress: _doctor?.address,
        awaitingDoctorApproval: !allConfirmed,
      );
      _step = 3;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingDoctor) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(
            child: CircularProgressIndicator(color: AppColors.patientTeal)),
      );
    }

    if (_doctor == null) {
      return Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text('Doctor not found')));
    }

    if (_step == 3 && _confirmed != null) {
      return BookingConfirmedView(
        booking: _confirmed!,
        onView: () => Navigator.popUntil(context, (r) => r.isFirst),
        onBookAnother: () => Navigator.pop(context),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.cardBgOf(context),
      appBar: AppBar(
        leading:
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: _back),
        title: Text('Book Appointment',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        backgroundColor: AppColors.cardBgOf(context),
        foregroundColor: AppColors.textPrimaryOf(context),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: PatientProfileFormStyles.constrainedScrollBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BookingStepHeader(
                    currentStep: _step,
                    totalSteps: 3,
                    title: _stepTitles[_step],
                  ),
                  const SizedBox(height: 20),
                  if (_step == 0)
                    _SlotStep(
                      draft: _draft,
                      slots: _slots,
                      loading: _loadingSlots,
                      schedule: _schedule,
                      shareReasonController: _slotShareReasonController,
                      onDate: (d) {
                        setState(() {
                          _slotShareReasonController.clear();
                          _draft = BookingDraft(
                            doctorId: _draft.doctorId,
                            doctorName: _draft.doctorName,
                            selectedDate: d,
                          );
                        });
                        unawaited(_loadSlotsForDate(d));
                      },
                      onSlot: (slot) {
                        if (!slot.isSelectable) return;
                        setState(() {
                          _slotShareReasonController.clear();
                          _draft = BookingDraft(
                            doctorId: _draft.doctorId,
                            doctorName: _draft.doctorName,
                            selectedDate: _draft.selectedDate,
                            selectedSlotId: slot.id,
                            selectedSlotLabel: slot.label,
                          );
                        });
                      },
                      onShareReasonType: (type) {
                        setState(() {
                          _draft.slotShareReasonType = type;
                          if (type != SlotShareReasonType.other) {
                            _draft.slotShareReasonText = '';
                            _slotShareReasonController.clear();
                          }
                        });
                      },
                      onShareReasonText: (text) {
                        setState(() => _draft.slotShareReasonText = text);
                      },
                    ),
                  if (_step == 1)
                    PatientProfileFormStyles.contentSurface(
                      context: context,
                      child: _DetailsStep(
                        draft: _draft,
                        familyMembers: _familyMembers,
                        getController: _getController,
                        onAddFamily: _addFamilyMember,
                        onToggleSelf: (v) => setState(() {
                          _draft.bookingForSelf = v ?? false;
                        }),
                        onSelfReasonChanged: (_) => setState(() {}),
                        onToggleFamily: (id, v) {
                          setState(() {
                            final ids =
                                List<String>.from(_draft.familyMemberIds);
                            if (v == true) {
                              if (!ids.contains(id)) ids.add(id);
                            } else {
                              ids.remove(id);
                            }
                            _draft.familyMemberIds = ids;
                          });
                        },
                      ),
                    ),
                  if (_step == 2)
                    PatientProfileFormStyles.contentSurface(
                      context: context,
                      child: _ReviewStep(
                        doctor: _doctor!,
                        draft: _draft,
                        patientNames: _patientNames(),
                        getController: _getController,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_step < 3)
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = PatientProfileFormStyles.resolveContentWidth(
                      context, constraints);
                  return Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: width,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: FilledButton(
                          onPressed: _canContinue() ? _next : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.patientTeal,
                            foregroundColor: AppColors.white,
                            disabledBackgroundColor:
                                AppColors.borderOf(context),
                            disabledForegroundColor:
                                AppColors.textSecondaryOf(context),
                            minimumSize: const Size(double.infinity, 52),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                            _step == 2
                                ? (DoctorProfileStore.autoAcceptForDoctor(
                                        widget.doctorId)
                                    ? 'Confirm booking'
                                    : 'Submit request')
                                : 'Continue',
                            style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: AppTypography.bodyLarge),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// --- Step widgets below (same file for cohesion) ---

class _SlotStep extends StatelessWidget {
  const _SlotStep({
    required this.draft,
    required this.slots,
    required this.loading,
    required this.schedule,
    required this.shareReasonController,
    required this.onDate,
    required this.onSlot,
    required this.onShareReasonType,
    required this.onShareReasonText,
  });

  final BookingDraft draft;
  final List<TimeSlot> slots;
  final bool loading;
  final DoctorAvailability schedule;
  final TextEditingController shareReasonController;
  final ValueChanged<DateTime> onDate;
  final ValueChanged<TimeSlot> onSlot;
  final ValueChanged<SlotShareReasonType?> onShareReasonType;
  final ValueChanged<String> onShareReasonText;

  static const int _maxBookingDaysAhead = 90;

  bool _isDaySelectable(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final lastDay = today.add(const Duration(days: _maxBookingDaysAhead));
    return !day.isBefore(today) && !day.isAfter(lastDay);
  }

  bool _isHoliday(DateTime date) {
    if (!_isDaySelectable(date)) return false;
    return FirestoreService.instance.doctorAvailability
        .isUnavailableDay(schedule, date);
  }

  String? _holidayMessage(DateTime date) {
    if (!_isDaySelectable(date)) return null;
    return FirestoreService.instance.doctorAvailability
        .unavailabilityReason(schedule, date);
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastDay = today.add(const Duration(days: _maxBookingDaysAhead));
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
      helpText: 'Select appointment date',
      selectableDayPredicate: (day) =>
          _isDaySelectable(day) && !_isHoliday(day),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context)
              .colorScheme
              .copyWith(primary: AppColors.patientTeal),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    onDate(picked);
  }

  Future<void> _pickTime(BuildContext context) async {
    if (loading) return;
    if (slots.isEmpty) {
      final selected = draft.selectedDate ?? DateTime.now();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _holidayMessage(selected) ??
                'No appointment times on this date. Please choose another date.',
          ),
        ),
      );
      return;
    }

    var initial = parseSlotTimeLabel(draft.selectedSlotLabel) ??
        parseSlotTimeLabel(slots
            .firstWhere((s) => s.isSelectable, orElse: () => slots.first)
            .label) ??
        const TimeOfDay(hour: 9, minute: 0);

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      initialEntryMode: TimePickerEntryMode.dialOnly,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
        child: Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context)
                .colorScheme
                .copyWith(primary: AppColors.patientTeal),
          ),
          child: child!,
        ),
      ),
    );
    if (picked == null) return;

    final matched = matchSlotForTime(slots, picked);
    if (matched == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('No matching time on this date. Please try another time.'),
        ),
      );
      return;
    }

    if (!matched.isSelectable) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('This time is unavailable. Please choose another time.'),
        ),
      );
      return;
    }

    if (!slotLabelsMatch(matched.label, formatSlotTimeLabel(picked)) &&
        context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Adjusted to nearest available slot: ${matched.label}'),
        ),
      );
    }

    onSlot(matched);
  }

  Widget _pickerTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    required String placeholder,
    required VoidCallback? onTap,
    bool enabled = true,
  }) {
    final hasValue = value.trim().isNotEmpty;
    return Material(
      color: AppColors.surfaceOf(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: enabled
                    ? AppColors.patientTeal
                    : AppColors.textSecondaryOf(context),
                size: 22,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.inter(
                          fontSize: AppTypography.labelMedium,
                          color: AppColors.textSecondaryOf(context)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasValue ? value : placeholder,
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodyLarge,
                        fontWeight: FontWeight.w600,
                        color: hasValue
                            ? AppColors.textPrimaryOf(context)
                            : AppColors.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              if (loading && label == 'Time')
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.patientTeal),
                )
              else
                Icon(
                  Icons.chevron_right,
                  color: AppColors.textSecondaryOf(context)
                      .withValues(alpha: enabled ? 0.8 : 0.4),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = draft.selectedDate ?? DateTime.now();
    TimeSlot? selectedSlot;
    for (final slot in slots) {
      if (slot.id == draft.selectedSlotId) {
        selectedSlot = slot;
        break;
      }
    }
    final needsShareReason =
        selectedSlot != null && selectedSlot.requiresShareReason;
    final selectableCount = slots.where((s) => s.isSelectable).length;
    final timeInPast = draft.selectedSlotLabel != null &&
        isSlotTimeInPast(selected, draft.selectedSlotLabel!);

    return PatientProfileFormStyles.contentSurface(
      context: context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.patientTeal.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.patientTeal.withValues(alpha: 0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline,
                    color: AppColors.patientTeal, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Choose a date, then pick any available time using the clock dial.',
                    style: GoogleFonts.inter(
                        fontSize: AppTypography.bodySmall,
                        height: 1.4,
                        color: AppColors.textPrimaryOf(context)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text('Appointment date',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _pickerTile(
            context: context,
            icon: Icons.calendar_today_outlined,
            label: 'Date',
            value: DateFormat('EEE, dd MMM yyyy').format(selected),
            placeholder: 'Tap to choose date',
            onTap: () => _pickDate(context),
          ),
          const SizedBox(height: 20),
          Text('Appointment time',
              style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _pickerTile(
            context: context,
            icon: Icons.schedule_outlined,
            label: 'Time',
            value: draft.selectedSlotLabel ?? '',
            placeholder: loading ? 'Loading times…' : 'Tap to choose time',
            onTap: () => _pickTime(context),
            enabled: !loading,
          ),
          if (timeInPast)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'This time has already passed. Please pick another time.',
                style: GoogleFonts.inter(
                    fontSize: AppTypography.labelMedium,
                    color: AppColors.error),
              ),
            ),
          if (!loading && slots.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              '$selectableCount time${selectableCount == 1 ? '' : 's'} available on this date',
              style: GoogleFonts.inter(
                  fontSize: AppTypography.labelMedium,
                  color: AppColors.textSecondaryOf(context)),
            ),
          ],
          if (!loading && slots.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _holidayMessage(selected) ??
                    'No appointment times on this date. The doctor may be on leave or fully booked.',
                style: GoogleFonts.inter(
                    fontSize: AppTypography.bodySmall,
                    color: AppColors.textSecondaryOf(context),
                    height: 1.4),
              ),
            ),
          if (selectedSlot != null && draft.selectedSlotLabel != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.patientTeal.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.patientTeal.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_available,
                      color: AppColors.patientTeal, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Selected: ${DateFormat('dd MMM yyyy').format(selected)} · ${draft.selectedSlotLabel}',
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.bodySmall,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (needsShareReason) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDBA74)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This slot already has ${selectedSlot.bookingCount} patient(s). '
                    'Maximum $kMaxPatientsPerTimeSlot can share the same time. Please tell us why you need this slot:',
                    style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        color: AppColors.textSecondaryOf(context),
                        height: 1.35),
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: AppColors.patientTeal,
                    title: const Text('Emergency'),
                    value: draft.slotShareReasonType ==
                        SlotShareReasonType.emergency,
                    onChanged: (checked) => onShareReasonType(
                      checked == true ? SlotShareReasonType.emergency : null,
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: AppColors.patientTeal,
                    title: const Text('Other'),
                    value:
                        draft.slotShareReasonType == SlotShareReasonType.other,
                    onChanged: (checked) => onShareReasonType(
                      checked == true ? SlotShareReasonType.other : null,
                    ),
                  ),
                  if (draft.slotShareReasonType ==
                      SlotShareReasonType.other) ...[
                    const SizedBox(height: 4),
                    TextField(
                      controller: shareReasonController,
                      onChanged: onShareReasonText,
                      decoration: PatientProfileFormStyles.fieldDecoration(
                        context,
                        labelText: 'Reason',
                        hintText: 'Why do you need this same time slot?',
                      ),
                      maxLines: 2,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailsStep extends StatelessWidget {
  const _DetailsStep({
    required this.draft,
    required this.familyMembers,
    required this.getController,
    required this.onAddFamily,
    required this.onToggleSelf,
    required this.onToggleFamily,
    required this.onSelfReasonChanged,
  });

  final BookingDraft draft;
  final List<FamilyMember> familyMembers;
  final TextEditingController Function(String) getController;
  final VoidCallback onAddFamily;
  final ValueChanged<bool?> onToggleSelf;
  final void Function(String, bool?) onToggleFamily;
  final ValueChanged<String> onSelfReasonChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Booking for',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        CheckboxListTile(
          title: const Text('Myself'),
          value: draft.bookingForSelf,
          onChanged: onToggleSelf,
          activeColor: AppColors.patientTeal,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
        ),
        if (draft.bookingForSelf)
          Padding(
            padding: const EdgeInsets.only(left: 32, bottom: 12),
            child: TextFormField(
              controller: getController('self'),
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              onChanged: onSelfReasonChanged,
              decoration: PatientProfileFormStyles.fieldDecoration(
                context,
                labelText: 'Reason for visit *',
                hintText: 'e.g. Fever, follow-up, chest pain (Required)',
                alignLabelWithHint: true,
              ),
            ),
          ),
        if (familyMembers.isNotEmpty)
          ...familyMembers.map((f) {
            final isSelected = draft.familyMemberIds.contains(f.id);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CheckboxListTile(
                  title: Text('${f.name} (${f.relation}, ${f.age}y)'),
                  value: isSelected,
                  onChanged: (v) => onToggleFamily(f.id, v),
                  activeColor: AppColors.patientTeal,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                if (isSelected)
                  Padding(
                    padding: const EdgeInsets.only(left: 32, bottom: 12),
                    child: TextFormField(
                      controller: getController(f.id),
                      maxLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: onSelfReasonChanged,
                      decoration: PatientProfileFormStyles.fieldDecoration(
                        context,
                        labelText: 'Reason for ${f.name} *',
                        hintText:
                            'e.g. Fever, routine checkup, pain (Required)',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ),
              ],
            );
          }),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: onAddFamily,
            icon: const Icon(Icons.person_add_outlined, size: 18),
            label: const Text('Add new family member'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.patientTeal,
              foregroundColor: AppColors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({
    required this.doctor,
    required this.draft,
    required this.patientNames,
    required this.getController,
  });

  final DoctorProfileDetail doctor;
  final BookingDraft draft;
  final List<String> patientNames;
  final TextEditingController Function(String) getController;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.patientTeal.withValues(alpha: 0.12),
              child: Text(doctor.name[0],
                  style: const TextStyle(color: AppColors.patientTeal)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Dr. ${doctor.name}',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                  Text(
                    '${DateFormat('dd MMM yyyy').format(draft.selectedDate!)} · ${draft.selectedSlotLabel}',
                    style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        color: AppColors.textSecondaryOf(context)),
                  ),
                  Text(
                    'In-clinic visit',
                    style: GoogleFonts.inter(
                        fontSize: AppTypography.labelMedium,
                        color: AppColors.patientTeal),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        Divider(height: 1, color: AppColors.borderOf(context)),
        SizedBox(height: 16),
        Text('Patient(s)',
            style: GoogleFonts.inter(
                fontSize: AppTypography.labelMedium,
                color: AppColors.textSecondaryOf(context))),
        const SizedBox(height: 4),
        Text(patientNames.join(', '),
            style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        if (draft.bookingForSelf) ...[
          const SizedBox(height: 12),
          Text('Your reason',
              style: GoogleFonts.inter(
                  fontSize: AppTypography.labelMedium,
                  color: AppColors.textSecondaryOf(context))),
          const SizedBox(height: 4),
          Text(
            getController('self').text.trim().isEmpty
                ? '—'
                : getController('self').text.trim(),
            style: GoogleFonts.inter(fontSize: AppTypography.bodySmall),
          ),
        ],
        for (final id in draft.familyMemberIds)
          if (getController(id).text.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Family reason',
                style: GoogleFonts.inter(
                    fontSize: AppTypography.labelMedium,
                    color: AppColors.textSecondaryOf(context))),
            const SizedBox(height: 4),
            Text(getController(id).text.trim(),
                style: GoogleFonts.inter(fontSize: AppTypography.bodySmall)),
          ],
      ],
    );
  }
}
