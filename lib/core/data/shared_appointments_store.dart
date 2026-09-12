import 'package:medibond/core/firebase/firestore_service.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/audio/chime_sound_service.dart';
import '../../core/firebase/firebase_bootstrap.dart';
import '../../core/session/patient_session.dart';
import '../../features/doctor/profile/data/doctor_profile_store.dart';
import '../../features/doctor/models/doctor_models.dart';
import '../../features/patient/profile/data/patient_profile_mock.dart';
import '../../features/patient/appointments/models/patient_appointment_models.dart';
import '../../features/patient/booking/models/booking_models.dart';

final _slotTimeFormat = DateFormat('hh:mm a');

String _normalizeSlotLabel(String label) {
  try {
    final parsed = _slotTimeFormat.parse(label.trim());
    return _slotTimeFormat.format(parsed);
  } catch (_) {
    return label.trim().toLowerCase();
  }
}

/// Single source of truth for patient bookings and doctor appointment queue.
class DoctorNectAppointmentRecord {
  DoctorNectAppointmentRecord({
    required this.id,
    required this.appointmentId,
    required this.doctorId,
    required this.doctorName,
    required this.specialization,
    required this.patientName,
    required this.patientAge,
    required this.patientGender,
    required this.dateTime,
    required this.slotLabel,
    required this.tokenNumber,
    required this.visitType,
    required this.patientStatus,
    required this.doctorStatus,
    this.clinicName,
    this.clinicAddress,
    this.mapsUrl,
    this.cancellationReason,
    this.diagnosis,
    this.hasPrescription = false,
    this.hasReport = false,
    this.hasReview = false,
    this.reviewRating,
    this.reviewId,
    this.reviewCreatedAt,
    this.labReports = const [],
    this.clinicalNotes,
    this.contactNumber,
    this.chiefComplaints = const [],
    this.patientId,
    this.source,
    this.symptoms = const [],
    this.observations = const [],
    this.bookedByName,
    this.patientRelation,
    this.slotShareReason,
    this.wasRescheduled = false,
  });

  final String id;
  final String? patientId;
  final String appointmentId;
  final String doctorId;
  final String doctorName;
  final String specialization;
  final String patientName;
  final int patientAge;
  final String patientGender;
  final DateTime dateTime;
  final String slotLabel;
  final int tokenNumber;
  final AppointmentType visitType;
  final PatientBookingStatus patientStatus;
  final AppointmentStatus doctorStatus;
  final String? clinicName;
  final String? clinicAddress;
  final String? mapsUrl;
  final String? cancellationReason;
  final String? diagnosis;
  final bool hasPrescription;
  final bool hasReport;
  final bool hasReview;
  final int? reviewRating;
  final String? reviewId;
  final DateTime? reviewCreatedAt;
  final List<String> labReports;
  final String? clinicalNotes;
  final String? contactNumber;
  final List<String> chiefComplaints;
  /// e.g. `walkin` for clinic walk-ins; null for app bookings.
  final String? source;
  final List<String> symptoms;
  final List<String> observations;
  /// Name of the account holder who made the booking (set only for family member appointments).
  final String? bookedByName;
  /// Relation to the account holder, e.g. Wife, Brother, Son.
  final String? patientRelation;
  /// Why this patient shares a slot with others (Emergency / custom reason).
  final String? slotShareReason;
  final bool wasRescheduled;

  bool get isCancelled => cancellationReason != null;

  DoctorNectAppointmentRecord copyWith({
    DateTime? dateTime,
    String? slotLabel,
    int? tokenNumber,
    PatientBookingStatus? patientStatus,
    AppointmentStatus? doctorStatus,
    String? cancellationReason,
    String? diagnosis,
    String? clinicalNotes,
    bool? hasPrescription,
    bool? hasReport,
    bool? hasReview,
    int? reviewRating,
    String? reviewId,
    DateTime? reviewCreatedAt,
    List<String>? symptoms,
    List<String>? chiefComplaints,
    List<String>? observations,
    List<String>? labReports,
    bool? wasRescheduled,
  }) {
    return DoctorNectAppointmentRecord(
      id: id,
      appointmentId: appointmentId,
      doctorId: doctorId,
      doctorName: doctorName,
      specialization: specialization,
      patientName: patientName,
      patientAge: patientAge,
      patientGender: patientGender,
      dateTime: dateTime ?? this.dateTime,
      slotLabel: slotLabel ?? this.slotLabel,
      tokenNumber: tokenNumber ?? this.tokenNumber,
      visitType: visitType,
      patientStatus: patientStatus ?? this.patientStatus,
      doctorStatus: doctorStatus ?? this.doctorStatus,
      clinicName: clinicName,
      clinicAddress: clinicAddress,
      mapsUrl: mapsUrl,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      diagnosis: diagnosis ?? this.diagnosis,
      hasPrescription: hasPrescription ?? this.hasPrescription,
      hasReport: hasReport ?? this.hasReport,
      hasReview: hasReview ?? this.hasReview,
      reviewRating: reviewRating ?? this.reviewRating,
      reviewId: reviewId ?? this.reviewId,
      reviewCreatedAt: reviewCreatedAt ?? this.reviewCreatedAt,
      labReports: labReports ?? this.labReports,
      clinicalNotes: clinicalNotes ?? this.clinicalNotes,
      contactNumber: contactNumber,
      chiefComplaints: chiefComplaints ?? this.chiefComplaints,
      patientId: patientId,
      source: source,
      symptoms: symptoms ?? this.symptoms,
      observations: observations ?? this.observations,
      bookedByName: bookedByName,
      patientRelation: patientRelation,
      slotShareReason: slotShareReason,
      wasRescheduled: wasRescheduled ?? this.wasRescheduled,
    );
  }

  String get chiefComplaintsLabel =>
      chiefComplaints.isEmpty ? '' : chiefComplaints.join(', ');
}

class SharedAppointmentsStore extends ChangeNotifier {
  SharedAppointmentsStore._();

  static final SharedAppointmentsStore instance = SharedAppointmentsStore._();

  final List<DoctorNectAppointmentRecord> _records = [];
  List<DoctorNectAppointmentRecord>? _recordsCache;
  final Map<String, DateTime> _lastDoctorRefresh = {};
  static const _doctorRefreshTtl = Duration(minutes: 2);

  List<DoctorNectAppointmentRecord> get records =>
      _recordsCache ??= List.unmodifiable(_records);

  void _invalidateCache() => _recordsCache = null;

  @override
  void notifyListeners() {
    _invalidateCache();
    super.notifyListeners();
  }

  void mergeFromFirestore(
    List<DoctorNectAppointmentRecord> remoteRecords, {
    bool pruneMissing = true,
  }) {
    final remoteIds = remoteRecords.map((r) => r.id).toSet();
    for (final remote in remoteRecords) {
      _records.removeWhere((r) => r.id == remote.id);
      _records.add(remote);
    }
    if (pruneMissing) {
      _records.removeWhere((r) => !remoteIds.contains(r.id));
    }
    _records.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    notifyListeners();
  }

  Future<void> refreshForDoctor(
    String doctorId, {
    bool preferCache = true,
    bool force = false,
  }) async {
    if (doctorId.isEmpty) return;

    final lastRefresh = _lastDoctorRefresh[doctorId];
    if (!force &&
        lastRefresh != null &&
        DateTime.now().difference(lastRefresh) < _doctorRefreshTtl &&
        _records.any((r) => r.doctorId == doctorId)) {
      return;
    }

    final remote = await FirestoreService.instance.appointment.fetchForDoctor(
      doctorId,
      preferCache: preferCache,
    );
    mergeFromFirestore(remote, pruneMissing: false);
    _lastDoctorRefresh[doctorId] = DateTime.now();
  }

  Future<void> refreshForPatient(String patientId) async {
    if (patientId.isEmpty) return;
    final remote = await FirestoreService.instance.appointment.fetchForPatient(
      patientId,
      preferCache: false,
    );
    mergeFromFirestore(remote);
  }

  void clearForSignOut() {
    _records.clear();
    _lastDoctorRefresh.clear();
    notifyListeners();
  }

  Future<void> _persist(
    DoctorNectAppointmentRecord record, {
    String? patientId,
    bool rethrowOnError = false, // FIXED: let booking flows surface write failures instead of only logging
  }) async {
    if (!FirebaseBootstrap.isReady) {
      if (rethrowOnError) {
        throw StateError('Could not save appointment. Firebase is not available.');
      }
      return;
    }
    final resolvedPatientId =
        patientId ?? record.patientId ?? PatientSession.loggedInPatientId;
    try {
      await FirestoreService.instance.appointment.save(
        record,
        patientId: resolvedPatientId.isNotEmpty ? resolvedPatientId : null,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Failed to persist appointment ${record.id}: $e\n$st');
      }
      if (rethrowOnError) rethrow; // FIXED: surface the error to the caller (e.g. booking flow)
    }
  }

  /// Applies an optimistic in-memory update, persists to Firestore, and rolls back on failure.
  Future<void> _updateRecordAtIndex(
    int index,
    DoctorNectAppointmentRecord updated, {
    String? patientId,
  }) async {
    final previous = _records[index];
    _records[index] = updated;
    notifyListeners();
    try {
      await _persist(updated, patientId: patientId, rethrowOnError: true);
    } catch (e) {
      _records[index] = previous;
      notifyListeners();
      rethrow;
    }
  }

  // FIXED: derive the appointment time from the slot label (e.g. "04:30 PM") instead of ignoring it
  static DateTime _dateTimeForSlot(DateTime date, String slotLabel) {
    final match = RegExp(r'(\d{1,2}):(\d{2})\s*([AaPp][Mm])?').firstMatch(slotLabel);
    if (match != null) {
      var hour = int.tryParse(match.group(1)!) ?? 0;
      final minute = int.tryParse(match.group(2)!) ?? 0;
      final mer = match.group(3)?.toUpperCase();
      if (mer == 'PM' && hour < 12) hour += 12;
      if (mer == 'AM' && hour == 12) hour = 0;
      return DateTime(date.year, date.month, date.day, hour, minute);
    }
    return DateTime(date.year, date.month, date.day, date.hour > 0 ? date.hour : 10, date.minute);
  }

  /// Single source of truth for reschedule: derive [dateTime] from [newDate] + [slotLabel].
  /// Throws rather than saving when the slot label cannot be parsed into a concrete time.
  static DateTime _resolveRescheduleDateTime(DateTime newDate, String slotLabel) {
    final trimmed = slotLabel.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(slotLabel, 'slotLabel', 'Cannot reschedule without a slot label.');
    }
    if (!RegExp(r'(\d{1,2}):(\d{2})\s*([AaPp][Mm])?').hasMatch(trimmed)) {
      throw StateError('Could not parse slot label "$trimmed" into a valid appointment time.');
    }
    return _dateTimeForSlot(newDate, trimmed);
  }

  static void _assertSlotDateTimeConsistent(DateTime dateTime, String slotLabel) {
    final expected = _dateTimeForSlot(
      DateTime(dateTime.year, dateTime.month, dateTime.day),
      slotLabel.trim(),
    );
    if (expected.hour != dateTime.hour || expected.minute != dateTime.minute) {
      throw StateError(
        'Appointment slot/time mismatch: slotLabel="$slotLabel" '
        'does not match dateTime=${dateTime.toIso8601String()}',
      );
    }
  }

  /// True when this patient has a prior non-cancelled appointment with [doctorId].
  bool _isReturningPatient({
    required String? patientId,
    required String patientName,
    required String doctorId,
  }) {
    if (doctorId.isEmpty) return false;

    final hasPriorById = patientId != null &&
        patientId.isNotEmpty &&
        _records.any(
          (r) =>
              r.doctorId == doctorId &&
              !r.isCancelled &&
              r.patientId != null &&
              r.patientId!.isNotEmpty &&
              r.patientId == patientId,
        );
    if (hasPriorById) return true;

    final normalizedName = patientName.trim().toLowerCase();
    if (normalizedName.isEmpty) return false;

    return _records.any(
      (r) =>
          r.doctorId == doctorId &&
          !r.isCancelled &&
          r.patientName.trim().toLowerCase() == normalizedName,
    );
  }

  List<PatientAppointment> patientAppointments() =>
      _records.map(_toPatient).toList();

  List<Appointment> doctorAppointments(String doctorId) => _records
      .where((r) => r.doctorId == doctorId)
      .map(_toDoctor)
      .toList()
    ..sort((a, b) => a.appointmentDate.compareTo(b.appointmentDate));

  List<Appointment> appointmentsForDoctorOnDate(String doctorId, DateTime date) {
    return _records
        .where((r) =>
            r.doctorId == doctorId &&
            r.dateTime.year == date.year &&
            r.dateTime.month == date.month &&
            r.dateTime.day == date.day)
        .map(_toDoctor)
        .toList()
      ..sort((a, b) => a.appointmentDate.compareTo(b.appointmentDate));
  }

  Set<DateTime> appointmentDatesForDoctorInMonth(
    String doctorId,
    int year,
    int month,
  ) {
    final dates = <DateTime>{};
    for (final r in _records) {
      if (r.doctorId != doctorId) continue;
      if (r.dateTime.year == year && r.dateTime.month == month) {
        dates.add(DateTime(r.dateTime.year, r.dateTime.month, r.dateTime.day));
      }
    }
    return dates;
  }

  List<Appointment> todayQueueForDoctor(String doctorId) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _records
        .where((r) =>
            r.doctorId == doctorId &&
            !r.isCancelled &&
            r.dateTime.year == today.year &&
            r.dateTime.month == today.month &&
            r.dateTime.day == today.day &&
            (r.doctorStatus == AppointmentStatus.pendingRequest ||
                r.doctorStatus == AppointmentStatus.waiting ||
                r.doctorStatus == AppointmentStatus.confirmed ||
                r.doctorStatus == AppointmentStatus.inProgress))
        .map(_toDoctor)
        .toList()
      ..sort((a, b) => a.appointmentDate.compareTo(b.appointmentDate));
  }

  List<Appointment> tomorrowForDoctor(String doctorId) {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    return _records
        .where((r) =>
            r.doctorId == doctorId &&
            !r.isCancelled &&
            r.dateTime.year == tomorrow.year &&
            r.dateTime.month == tomorrow.month &&
            r.dateTime.day == tomorrow.day)
        .map(_toDoctor)
        .toList();
  }

  List<Appointment> upcomingForDoctor(String doctorId, {int limit = 30}) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final list = _records
        .where((r) {
          if (r.doctorId != doctorId || r.isCancelled) return false;
          final apptDay = DateTime(r.dateTime.year, r.dateTime.month, r.dateTime.day);
          if (!apptDay.isAfter(todayStart)) return false;
          return r.doctorStatus == AppointmentStatus.pendingRequest ||
              r.doctorStatus == AppointmentStatus.waiting ||
              r.doctorStatus == AppointmentStatus.confirmed ||
              r.doctorStatus == AppointmentStatus.inProgress;
        })
        .map(_toDoctor)
        .toList()
      ..sort((a, b) => a.appointmentDate.compareTo(b.appointmentDate));

    return list.length > limit ? list.sublist(0, limit) : list;
  }

  DoctorNectAppointmentRecord? findRecordById(String id) {
    for (final r in _records) {
      if (r.id == id) return r;
    }
    return null;
  }

  PatientAppointment? patientAppointmentForTarget(String? targetId) {
    if (targetId == null) return null;
    for (final r in _records) {
      if (r.appointmentId == targetId || r.id == targetId) {
        return _toPatient(r);
      }
    }
    return null;
  }

  Appointment? doctorAppointmentForTarget(String? targetId, String doctorId) {
    if (targetId == null) return null;
    for (final r in _records) {
      if (r.doctorId == doctorId &&
          (r.appointmentId == targetId || r.id == targetId)) {
        return _toDoctor(r);
      }
    }
    return null;
  }

  /// Returns `true` when the doctor auto-confirmed the request.
  Future<bool> addBooking({
    required String doctorId,
    required String doctorName,
    required String specialization,
    required DateTime date,
    required String slotLabel,
    required String appointmentId,
    required int tokenNumber,
    required String patientName,
    required int patientAge,
    required String patientGender,
    required String? clinicName,
    required String? clinicAddress,
    required String? mapsUrl,
    String? reasonForVisit,
    String? bookedByName,
    String? patientRelation,
    String? slotShareReason,
  }) async {
    if (bookingCountForSlot(doctorId, date, slotLabel) >= kMaxPatientsPerTimeSlot) {
      return false;
    }
    if (isSlotTimeInPast(date, slotLabel)) {
      return false;
    }
    final id = 'pa${DateTime.now().millisecondsSinceEpoch}';
    final dateTime = _dateTimeForSlot(date, slotLabel); // FIXED: apply the booked slot's time instead of ignoring slotLabel
    final autoAccept = DoctorProfileStore.autoAcceptForDoctor(doctorId);
    final patientStatus =
        autoAccept ? PatientBookingStatus.confirmed : PatientBookingStatus.pending;
    final doctorStatus =
        autoAccept ? AppointmentStatus.confirmed : AppointmentStatus.pendingRequest;
    final patientId = PatientSession.loggedInPatientId;
    final visitType = _isReturningPatient(
          patientId: patientId,
          patientName: patientName,
          doctorId: doctorId,
        )
        ? AppointmentType.followUp
        : AppointmentType.newVisit;

    _records.add(
      DoctorNectAppointmentRecord(
        id: id,
        appointmentId: appointmentId,
        doctorId: doctorId,
        doctorName: doctorName,
        specialization: specialization,
        patientName: patientName,
        patientAge: patientAge,
        patientGender: AppConstants.normalizePatientGender(patientGender),
        dateTime: dateTime,
        slotLabel: slotLabel,
        tokenNumber: tokenNumber,
        visitType: visitType,
        patientStatus: patientStatus,
        doctorStatus: doctorStatus,
        clinicName: clinicName,
        clinicAddress: clinicAddress,
        mapsUrl: mapsUrl,
        contactNumber: PatientProfileMock.profile.mobile,
        chiefComplaints: _normalizeTags(
          reasonForVisit != null && reasonForVisit.trim().isNotEmpty
              ? [reasonForVisit.trim()]
              : const [],
        ),
        patientId: patientId,
        bookedByName: bookedByName,
        patientRelation: patientRelation,
        slotShareReason: slotShareReason,
      ),
    );
    notifyListeners();
    try {
      await _persist(_records.last, patientId: patientId, rethrowOnError: true); // FIXED: surface write failure
    } catch (e) {
      // FIXED: roll back the optimistic record so we never show a confirmed booking that wasn't saved
      _records.removeWhere((r) => r.id == id);
      notifyListeners();
      rethrow;
    }
    return autoAccept;
  }

  static List<String> _normalizeTags(List<String> raw) {
    final out = <String>[];
    final seen = <String>{};
    for (final item in raw) {
      final s = item.trim();
      if (s.isEmpty) continue;
      final key = s.toLowerCase();
      if (seen.add(key)) out.add(s);
    }
    return out;
  }

  /// Next queue token for a doctor on a calendar day (1, 2, 3â€¦ resets each date).
  int nextTokenNumberForDoctorOnDate(String doctorId, DateTime date) {
    final tokens = _records
        .where(
          (r) =>
              r.doctorId == doctorId &&
              r.dateTime.year == date.year &&
              r.dateTime.month == date.month &&
              r.dateTime.day == date.day,
        )
        .map((r) => r.tokenNumber);
    if (tokens.isEmpty) return 1;
    return tokens.reduce((a, b) => a > b ? a : b) + 1;
  }

  int bookingCountForSlot(String doctorId, DateTime date, String slotLabel) {
    final target = _normalizeSlotLabel(slotLabel);
    return _records.where((r) {
      return r.doctorId == doctorId &&
          !r.isCancelled &&
          r.dateTime.year == date.year &&
          r.dateTime.month == date.month &&
          r.dateTime.day == date.day &&
          _normalizeSlotLabel(r.slotLabel) == target;
    }).length;
  }

  /// Registers a walk-in patient at the clinic (no patient app account).
  Future<bool> addWalkInAppointment({
    required String doctorId,
    required String doctorName,
    required String specialization,
    required String patientName,
    required int patientAge,
    required String patientGender,
    required DateTime dateTime,
    String? contactNumber,
    List<String> chiefComplaints = const [],
  }) async {
    if (doctorId.isEmpty) return false;

    final ms = DateTime.now().millisecondsSinceEpoch;
    final patientId = 'wi$ms';
    final id = 'pa$ms';
    final appointmentId = 'APT${ms % 100000}';
    final slotLabel = DateFormat('hh:mm a').format(dateTime);

    final day = DateTime(dateTime.year, dateTime.month, dateTime.day);
    final tokenNumber = nextTokenNumberForDoctorOnDate(doctorId, day);

    final visitType = _isReturningPatient(
          patientId: patientId,
          patientName: patientName,
          doctorId: doctorId,
        )
        ? AppointmentType.followUp
        : AppointmentType.newVisit;

    final record = DoctorNectAppointmentRecord(
      id: id,
      appointmentId: appointmentId,
      doctorId: doctorId,
      doctorName: doctorName,
      specialization: specialization,
      patientName: patientName.trim(),
      patientAge: patientAge,
      patientGender: AppConstants.normalizePatientGender(patientGender),
      dateTime: dateTime,
      slotLabel: slotLabel,
      tokenNumber: tokenNumber,
      visitType: visitType,
      patientStatus: PatientBookingStatus.confirmed,
      doctorStatus: AppointmentStatus.confirmed,
      contactNumber: contactNumber?.trim().isNotEmpty == true ? contactNumber!.trim() : null,
      chiefComplaints: _normalizeTags(chiefComplaints),
      patientId: patientId,
      source: 'walkin',
    );

    _records.add(record);
    notifyListeners();
    await _persist(record, patientId: patientId);
    return true;
  }

  Future<void> reschedulePatient({
    required String recordId,
    required DateTime newDate,
    required String newSlotLabel,
    required int? newToken,
  }) async {
    final i = _records.indexWhere((r) => r.id == recordId);
    if (i < 0) return;
    final old = _records[i];

    if (old.doctorStatus == AppointmentStatus.completed ||
        old.doctorStatus == AppointmentStatus.inProgress ||
        old.doctorStatus == AppointmentStatus.noShow) {
      throw StateError('Cannot reschedule an appointment that is already ${old.doctorStatus.name}.');
    }

    final trimmedSlot = newSlotLabel.trim();
    final newDateTime = _resolveRescheduleDateTime(newDate, trimmedSlot);
    _assertSlotDateTimeConsistent(newDateTime, trimmedSlot);
    await _updateRecordAtIndex(
      i,
      old.copyWith(
        dateTime: newDateTime,
        slotLabel: trimmedSlot,
        tokenNumber: newToken ?? old.tokenNumber,
        patientStatus: PatientBookingStatus.confirmed,
        doctorStatus: AppointmentStatus.confirmed,
        cancellationReason: null,
        wasRescheduled: true,
      ),
      patientId: old.patientId,
    );
  }

  Future<void> rescheduleByDoctor({
    required String recordId,
    required DateTime newDate,
    required String newSlotLabel,
  }) async {
    final i = _records.indexWhere((r) => r.id == recordId);
    if (i < 0) return;
    final old = _records[i];
    final trimmedSlot = newSlotLabel.trim();
    final newDateTime = _resolveRescheduleDateTime(newDate, trimmedSlot);
    _assertSlotDateTimeConsistent(newDateTime, trimmedSlot);
    await _updateRecordAtIndex(
      i,
      old.copyWith(
        dateTime: newDateTime,
        slotLabel: trimmedSlot,
        doctorStatus: AppointmentStatus.confirmed,
        wasRescheduled: true,
      ),
      patientId: old.patientId,
    );
  }

  Future<void> cancelByPatient(String recordId, {required String reason}) async {
    final i = _records.indexWhere((r) => r.id == recordId);
    if (i < 0) return;
    final old = _records[i];

    if (old.doctorStatus == AppointmentStatus.completed ||
        old.doctorStatus == AppointmentStatus.inProgress ||
        old.doctorStatus == AppointmentStatus.noShow) {
      throw StateError('Cannot cancel an appointment that is already ${old.doctorStatus.name}.');
    }

    await _updateRecordAtIndex(
      i,
      old.copyWith(
        cancellationReason: reason,
        doctorStatus: AppointmentStatus.cancelled,
      ),
      patientId: old.patientId,
    );
  }

  Future<void> cancelByDoctor(String recordId, {required String reason}) async {
    final i = _records.indexWhere((r) => r.id == recordId);
    if (i < 0) return;
    final old = _records[i];
    await _updateRecordAtIndex(
      i,
      old.copyWith(
        cancellationReason: reason,
        doctorStatus: AppointmentStatus.cancelled,
      ),
      patientId: old.patientId,
    );
  }

  Future<void> acceptAppointment(String recordId) async {
    await acceptAppointments([recordId]);
  }

  Future<void> acceptAppointments(Iterable<String> recordIds) async {
    for (final recordId in recordIds) {
      final i = _records.indexWhere((r) => r.id == recordId);
      if (i < 0) continue;
      final current = _records[i];
      if (current.doctorStatus == AppointmentStatus.confirmed ||
          current.doctorStatus == AppointmentStatus.inProgress ||
          current.doctorStatus == AppointmentStatus.completed ||
          current.doctorStatus == AppointmentStatus.waiting) {
        continue;
      }
      await _updateRecordAtIndex(
        i,
        current.copyWith(
          doctorStatus: AppointmentStatus.confirmed,
          patientStatus: PatientBookingStatus.confirmed,
        ),
        patientId: current.patientId,
      );
    }
    ChimeSoundService.playAcceptChime();
  }

  Future<void> declineAppointment(String recordId, {String reason = 'Declined by doctor'}) {
    return cancelByDoctor(recordId, reason: reason);
  }

  Future<void> updateDoctorStatus(String recordId, AppointmentStatus status) async {
    final i = _records.indexWhere((r) => r.id == recordId);
    if (i < 0) return;
    final patientStatus = switch (status) {
      AppointmentStatus.pendingRequest => PatientBookingStatus.pending,
      AppointmentStatus.confirmed => PatientBookingStatus.confirmed,
      AppointmentStatus.waiting => PatientBookingStatus.confirmed,
      AppointmentStatus.inProgress => PatientBookingStatus.confirmed,
      AppointmentStatus.completed => PatientBookingStatus.confirmed,
      AppointmentStatus.cancelled => _records[i].patientStatus,
      AppointmentStatus.noShow => _records[i].patientStatus,
    };
    _records[i] = _records[i].copyWith(
      doctorStatus: status,
      patientStatus: patientStatus,
    );
    notifyListeners();
    await _persist(_records[i]);
  }

  void markPrescriptionForRecord(String recordId) {
    unawaited(saveConsultationOutcome(recordId: recordId, hasPrescription: true));
  }

  Future<void> saveChiefComplaints({
    required String recordId,
    required List<String> chiefComplaints,
  }) async {
    final i = _records.indexWhere((r) => r.id == recordId);
    if (i < 0) return;
    _records[i] = _records[i].copyWith(chiefComplaints: _normalizeTags(chiefComplaints));
    notifyListeners();
    await _persist(_records[i]);
  }

  Future<void> saveObservations({
    required String recordId,
    required List<String> observations,
  }) async {
    final i = _records.indexWhere((r) => r.id == recordId);
    if (i < 0) return;
    _records[i] = _records[i].copyWith(observations: _normalizeTags(observations));
    notifyListeners();
    await _persist(_records[i]);
  }

  Future<void> saveSymptoms({
    required String recordId,
    required List<String> symptoms,
  }) async {
    final i = _records.indexWhere((r) => r.id == recordId);
    if (i < 0) return;
    final normalized = <String>[];
    final seen = <String>{};
    for (final raw in symptoms) {
      final s = raw.trim();
      if (s.isEmpty) continue;
      final key = s.toLowerCase();
      if (seen.add(key)) normalized.add(s);
    }
    _records[i] = _records[i].copyWith(symptoms: normalized);
    notifyListeners();
    await _persist(_records[i]);
  }

  Future<void> appendLabReports({
    required String recordId,
    required List<String> reports,
  }) async {
    final i = _records.indexWhere((r) => r.id == recordId);
    if (i < 0) return;
    final old = _records[i];
    final seen = old.labReports.map((r) => r.toLowerCase()).toSet();
    final merged = [...old.labReports];
    for (final report in reports) {
      final trimmed = report.trim();
      if (trimmed.isEmpty) continue;
      final key = trimmed.toLowerCase();
      if (seen.add(key)) merged.add(trimmed);
    }
    if (merged.length == old.labReports.length) return;
    _records[i] = old.copyWith(labReports: merged, hasReport: true);
    notifyListeners();
    await _persist(_records[i]);
  }

  Future<void> saveConsultationOutcome({
    required String recordId,
    String? diagnosis,
    String? clinicalNotes,
    bool? hasPrescription,
    bool? hasReport,
    bool markCompleted = false,
  }) async {
    final i = _records.indexWhere((r) => r.id == recordId);
    if (i < 0) return;
    final old = _records[i];
    final trimmedDiagnosis = diagnosis?.trim();
    _records[i] = old.copyWith(
      diagnosis: trimmedDiagnosis?.isNotEmpty == true ? trimmedDiagnosis : null,
      clinicalNotes: clinicalNotes?.trim().isNotEmpty == true ? clinicalNotes!.trim() : null,
      hasPrescription: hasPrescription,
      hasReport: hasReport,
      doctorStatus: markCompleted ? AppointmentStatus.completed : null,
      patientStatus: markCompleted ? PatientBookingStatus.confirmed : null,
    );
    notifyListeners();
    await _persist(_records[i]);
  }

  Future<bool> submitReview({
    required String recordId,
    required int rating,
    required String comment,
  }) async {
    final i = _records.indexWhere((r) => r.id == recordId);
    if (i < 0) return false;
    final r = _records[i];

    final patientId = r.patientId ?? PatientSession.loggedInPatientId;
    if (patientId.isEmpty) return false;

    final patientName = PatientProfileMock.profile.name.isNotEmpty
        ? PatientProfileMock.profile.name
        : (PatientSession.loggedInPatientName.isNotEmpty
            ? PatientSession.loggedInPatientName
            : r.patientName);

    final reviewId = await FirestoreService.instance.review.submitReview(
      patientId: patientId,
      doctorId: r.doctorId,
      appointmentId: r.appointmentId,
      rating: rating,
      comment: comment,
      patientName: patientName,
    );

    if (reviewId == null) return false;

    final createdAt = DateTime.now();
    _records[i] = r.copyWith(
      hasReview: true,
      reviewRating: rating,
      reviewId: reviewId,
      reviewCreatedAt: createdAt,
    );
    notifyListeners();
    await _persist(_records[i]);
    return true;
  }

  Future<bool> updateReview({
    required String recordId,
    required int rating,
    required String comment,
  }) async {
    final i = _records.indexWhere((r) => r.id == recordId);
    if (i < 0) return false;
    final r = _records[i];
    final reviewId = r.reviewId;
    if (reviewId == null || reviewId.isEmpty) return false;

    final patientId = r.patientId ?? PatientSession.loggedInPatientId;
    if (patientId.isEmpty) return false;

    final updated = await FirestoreService.instance.review.updateReview(
      reviewId: reviewId,
      patientId: patientId,
      rating: rating,
      comment: comment,
    );
    if (!updated) return false;

    _records[i] = r.copyWith(reviewRating: rating);
    notifyListeners();
    await _persist(_records[i]);
    return true;
  }

  Future<bool> updateReviewByReviewId({
    required String reviewId,
    required int rating,
    required String comment,
  }) async {
    final patientId = PatientSession.loggedInPatientId;
    if (patientId.isEmpty) return false;

    final updated = await FirestoreService.instance.review.updateReview(
      reviewId: reviewId,
      patientId: patientId,
      rating: rating,
      comment: comment,
    );
    if (!updated) return false;

    final i = _records.indexWhere((r) => r.reviewId == reviewId);
    if (i >= 0) {
      _records[i] = _records[i].copyWith(reviewRating: rating);
      notifyListeners();
      await _persist(_records[i]);
    }
    return true;
  }

  static PatientAppointment _toPatient(DoctorNectAppointmentRecord r) {
    return PatientAppointment(
      id: r.id,
      appointmentId: r.appointmentId,
      doctorId: r.doctorId,
      doctorName: r.doctorName,
      specialization: r.specialization,
      dateTime: r.dateTime,
      tokenNumber: r.tokenNumber,
      status: r.patientStatus,
      slotLabel: r.slotLabel, // FIXED: pass the booked slot label through to the UI
      clinicName: r.clinicName,
      clinicAddress: r.clinicAddress,
      mapsUrl: r.mapsUrl,
      diagnosis: r.diagnosis,
      hasPrescription: r.hasPrescription,
      hasReport: r.hasReport,
      hasReview: r.hasReview,
      reviewRating: r.reviewRating,
      reviewId: r.reviewId,
      reviewCreatedAt: r.reviewCreatedAt,
      cancellationReason: r.cancellationReason,
      labReports: r.labReports,
      clinicalNotes: r.clinicalNotes,
      reasonForVisit: r.chiefComplaintsLabel,
    );
  }

  static Appointment _toDoctor(DoctorNectAppointmentRecord r) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final apptDay = DateTime(r.dateTime.year, r.dateTime.month, r.dateTime.day);
    return Appointment(
      id: r.id,
      tokenNumber: r.tokenNumber,
      patientName: r.patientName,
      age: r.patientAge,
      gender: r.patientGender,
      timeSlot: r.slotLabel,
      appointmentDate: r.dateTime,
      type: r.visitType,
      status: r.doctorStatus,
      isToday: apptDay == today,
      contactNumber: r.contactNumber,
      chiefComplaints: r.chiefComplaints,
      symptoms: r.symptoms,
      bookedByName: r.bookedByName,
      patientRelation: r.patientRelation,
      slotShareReason: r.slotShareReason,
      reports: r.labReports
          .map(
            (name) => PatientReport(
              id: name,
              name: name,
              fileType: name.toLowerCase().endsWith('.pdf') ? 'pdf' : 'image',
            ),
          )
          .toList(),
    );
  }
}
