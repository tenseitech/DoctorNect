import 'package:medibond/core/firebase/firestore_service.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../features/doctor/profile/data/doctor_profile_store.dart';
import '../../features/patient/profile/data/patient_profile_mock.dart';
import '../session/doctor_session.dart';
import '../session/patient_session.dart';
import 'app_notification.dart';
import 'doctor_notification_emitter.dart';
import 'doctor_notification_trigger.dart';
import 'notification_read_store.dart';
import 'patient_notification_trigger.dart';



typedef NotificationListener = void Function(AppNotification notification);



/// In-app notification center â€” no FCM/SMS; alerts appear when events fire in DoctorNect.

class InAppNotificationService extends ChangeNotifier {

  InAppNotificationService._();



  static final instance = InAppNotificationService._();



  final List<AppNotification> _doctor = [];

  final List<AppNotification> _patient = [];

  final Set<String> _doctorDedupeKeys = {};

  final Set<String> _patientDedupeKeys = {};

  final Set<String> _doctorReadKeys = {};

  final Set<String> _patientReadKeys = {};

  final Set<String> _doctorFirestoreIds = {};

  final Set<String> _patientFirestoreIds = {};

  List<AppNotification>? _lastPatientFirestoreSnapshot;

  NotificationListener? onDoctorNotificationArrived;

  NotificationListener? onPatientNotificationArrived;

  void clearAllNotifications() {
    _doctor.clear();
    _patient.clear();
    _doctorDedupeKeys.clear();
    _patientDedupeKeys.clear();
    _doctorReadKeys.clear();
    _patientReadKeys.clear();
    _doctorFirestoreIds.clear();
    _patientFirestoreIds.clear();
    _lastPatientFirestoreSnapshot = null;
    notifyListeners();
  }

  static String _storageKey(AppNotification notification) {
    final dedupe = notification.dedupeKey?.trim();
    if (dedupe != null && dedupe.isNotEmpty) return dedupe;

    final targetId = notification.targetId?.trim();
    if (targetId != null && targetId.isNotEmpty) {
      final patientTrigger = notification.patientTrigger?.name;
      if (patientTrigger != null && patientTrigger.isNotEmpty) {
        return 'p_${patientTrigger}_$targetId';
      }
      final doctorTrigger = notification.doctorTrigger?.name;
      if (doctorTrigger != null && doctorTrigger.isNotEmpty) {
        return 'd_${doctorTrigger}_$targetId';
      }
      return 'target_$targetId';
    }

    return notification.id;
  }

  /// Clears in-memory notification state on logout so the next login reloads from disk.
  void clearSessionState() {
    _doctor.clear();
    _patient.clear();
    _doctorDedupeKeys.clear();
    _patientDedupeKeys.clear();
    _doctorReadKeys.clear();
    _patientReadKeys.clear();
    _doctorFirestoreIds.clear();
    _patientFirestoreIds.clear();
    _lastPatientFirestoreSnapshot = null;
    notifyListeners();
  }

  /// Re-evaluates patient inbox items when notification preferences change.
  void onPatientNotificationPrefsChanged() {
    if (_lastPatientFirestoreSnapshot != null) {
      mergePatientFirestoreNotifications(List<AppNotification>.from(_lastPatientFirestoreSnapshot!));
    }
    refilterPatientLocalInbox();
  }

  void rememberPatientFirestoreSnapshot(List<AppNotification> snapshot) {
    _lastPatientFirestoreSnapshot = List<AppNotification>.from(snapshot);
  }

  /// Removes local-only patient notifications disallowed by current prefs.
  void refilterPatientLocalInbox() {
    var changed = false;
    for (var i = _patient.length - 1; i >= 0; i--) {
      final notification = _patient[i];
      if (_patientFirestoreIds.contains(notification.id)) continue;
      if (_shouldHidePatientNotification(notification)) {
        _patient.removeAt(i);
        _patientDedupeKeys.remove(_storageKey(notification));
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  bool _shouldHidePatientNotification(AppNotification notification) {
    if (_isPrescriptionExpiringAlert(notification)) return true;
    final trigger = notification.patientTrigger;
    if (trigger == null) return false;
    return !_allowsPatient(trigger);
  }

  Future<void> warmUpReadState(NotificationAudience audience) async {
    if (audience == NotificationAudience.doctor) {
      final userId = DoctorSession.loggedInDoctorId;
      if (userId.isEmpty) return;
      _doctorReadKeys
        ..clear()
        ..addAll(await NotificationReadStore.load(audience: audience, userId: userId));
      _applyPersistedReadToInbox(NotificationAudience.doctor);
      return;
    }

    final userId = PatientSession.loggedInPatientId;
    if (userId.isEmpty) return;
    _patientReadKeys
      ..clear()
      ..addAll(await NotificationReadStore.load(audience: audience, userId: userId));
    _applyPersistedReadToInbox(NotificationAudience.patient);
  }

  void _applyPersistedReadToInbox(NotificationAudience audience) {
    final list = audience == NotificationAudience.doctor ? _doctor : _patient;
    var changed = false;
    for (var i = 0; i < list.length; i++) {
      if (!list[i].isRead && _isPersistedRead(audience, list[i])) {
        list[i] = list[i].copyWith(isRead: true);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  bool _isPersistedRead(NotificationAudience audience, AppNotification notification) {
    final keys = audience == NotificationAudience.doctor ? _doctorReadKeys : _patientReadKeys;
    return keys.contains(_storageKey(notification));
  }

  Future<void> _persistAllRead(
    NotificationAudience audience,
    Iterable<AppNotification> notifications,
  ) async {
    final userId = audience == NotificationAudience.doctor
        ? DoctorSession.loggedInDoctorId
        : PatientSession.loggedInPatientId;
    if (userId.isEmpty) return;

    final keys = audience == NotificationAudience.doctor ? _doctorReadKeys : _patientReadKeys;
    final toPersist = <String>[];
    for (final notification in notifications) {
      final key = _storageKey(notification);
      if (key.isEmpty) continue;
      if (keys.add(key)) toPersist.add(key);
    }
    if (toPersist.isEmpty) return;

    await NotificationReadStore.markAllRead(
      audience: audience,
      userId: userId,
      keys: toPersist,
    );
  }

  AppNotification _withPersistedReadState(
    NotificationAudience audience,
    AppNotification notification,
  ) {
    if (!_isPersistedRead(audience, notification)) return notification;
    return notification.copyWith(isRead: true);
  }



  List<AppNotification> get doctorInbox => List.unmodifiable(_doctor);

  List<AppNotification> get patientInbox =>
      List.unmodifiable(_patient.where((n) => !_isPrescriptionExpiringAlert(n)));



  int get unreadDoctorCount => _doctor.where((n) => !n.isRead).length;



  int get unreadPatientCount =>
      _patient.where((n) => !n.isRead && !_isPrescriptionExpiringAlert(n)).length;



  /// Retired alert type â€” hide legacy in-memory items (dedupe key / title).

  static bool _isPrescriptionExpiringAlert(AppNotification n) {

    if (n.dedupeKey != null && n.dedupeKey!.startsWith('rx_exp_')) return true;

    return n.title.toLowerCase().contains('prescription expiring');

  }



  bool _allowsDoctor(DoctorNotificationTrigger trigger) {

    final p = DoctorProfileStore.instance.profile;

    return switch (trigger) {

      DoctorNotificationTrigger.newAppointmentBooked => true,

      DoctorNotificationTrigger.appointmentCancelledByPatient => true,

      DoctorNotificationTrigger.appointmentReminderTomorrow ||

      DoctorNotificationTrigger.appointmentReminderToday ||

      DoctorNotificationTrigger.nextPatientReminder =>

        p.appointmentReminders,

      _ => true,

    };

  }



  bool _allowsPatient(PatientNotificationTrigger trigger) {

    final p = PatientProfileMock.notificationPrefs;

    return switch (trigger) {

      PatientNotificationTrigger.appointmentReminderTomorrow ||

      PatientNotificationTrigger.appointmentReminderTwoHours ||

      PatientNotificationTrigger.appointmentReminderThirtyMin =>

        p.appointmentReminders,

      PatientNotificationTrigger.labCollectionReminder ||

      PatientNotificationTrigger.phlebotomistOnTheWay ||

      PatientNotificationTrigger.labReportReady ||

      PatientNotificationTrigger.labBookingAccepted ||

      PatientNotificationTrigger.labBookingDeclined ||

      PatientNotificationTrigger.labOrderSent =>

        p.labReportAlert,

      PatientNotificationTrigger.labBookingUpdate ||

      PatientNotificationTrigger.pharmacyDeliveryUpdate =>

        true,

      PatientNotificationTrigger.medicineReminder => p.medicationReminders,

      PatientNotificationTrigger.healthTipOfDay => p.healthTips,

      _ => true,

    };

  }



  void addDoctor(AppNotification notification) {

    if (notification.doctorTrigger != null && !_allowsDoctor(notification.doctorTrigger!)) {

      return;

    }

    final storageKey = _storageKey(notification);
    if (_doctorDedupeKeys.contains(storageKey)) return;
    _doctorDedupeKeys.add(storageKey);

    final resolved = _withPersistedReadState(NotificationAudience.doctor, notification);

    _doctor.insert(0, resolved);

    if (!resolved.isRead) {
      onDoctorNotificationArrived?.call(resolved);
    }

    notifyListeners();

  }

  /// Replaces Firestore-backed doctor inbox items with the latest remote snapshot.
  void mergeDoctorFirestoreNotifications(List<AppNotification> fromFirestore) {
    for (final id in _doctorFirestoreIds) {
      final index = _doctor.indexWhere((n) => n.id == id);
      if (index < 0) continue;
      final removed = _doctor.removeAt(index);
      _doctorDedupeKeys.remove(_storageKey(removed));
    }
    _doctorFirestoreIds.clear();

    for (final notification in fromFirestore) {
      if (notification.doctorTrigger != null &&
          !_allowsDoctor(notification.doctorTrigger!)) {
        continue;
      }

      _doctorFirestoreIds.add(notification.id);
      _doctorDedupeKeys.add(_storageKey(notification));
      _doctor.add(notification);
    }

    _doctor.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
  }

  /// Replaces Firestore-backed patient inbox items with the latest remote snapshot.
  void mergePatientFirestoreNotifications(List<AppNotification> fromFirestore) {
    rememberPatientFirestoreSnapshot(fromFirestore);

    for (final id in _patientFirestoreIds) {
      final index = _patient.indexWhere((n) => n.id == id);
      if (index < 0) continue;
      final removed = _patient.removeAt(index);
      _patientDedupeKeys.remove(_storageKey(removed));
    }
    _patientFirestoreIds.clear();

    for (final notification in fromFirestore) {
      if (_isPrescriptionExpiringAlert(notification)) continue;
      if (notification.patientTrigger != null &&
          !_allowsPatient(notification.patientTrigger!)) {
        continue;
      }

      _patientFirestoreIds.add(notification.id);
      _patientDedupeKeys.add(_storageKey(notification));
      _patient.add(notification);
    }

    _patient.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    notifyListeners();
  }

  void addPatient(AppNotification notification) {

    if (_isPrescriptionExpiringAlert(notification)) return;

    if (notification.patientTrigger != null && !_allowsPatient(notification.patientTrigger!)) {

      return;

    }

    final storageKey = _storageKey(notification);
    if (_patientDedupeKeys.contains(storageKey)) return;
    _patientDedupeKeys.add(storageKey);

    final resolved = _withPersistedReadState(NotificationAudience.patient, notification);

    _patient.insert(0, resolved);

    if (!resolved.isRead) {
      onPatientNotificationArrived?.call(resolved);
    }

    notifyListeners();

  }



  Future<void> markDoctorRead(String id) async {
    final index = _doctor.indexWhere((n) => n.id == id);
    if (index < 0 || _doctor[index].isRead) return;

    final readKey = _storageKey(_doctor[index]);
    final matching = _doctor.where((n) => !n.isRead && _storageKey(n) == readKey).toList();
    if (matching.isEmpty) return;

    final firestoreUnreadIds = <String>[];
    final updatedMatching = <AppNotification>[];

    for (final notification in matching) {
      final i = _doctor.indexWhere((n) => n.id == notification.id);
      if (i < 0) continue;
      final updated = _doctor[i].copyWith(isRead: true);
      _doctor[i] = updated;
      updatedMatching.add(updated);
      if (_doctorFirestoreIds.contains(updated.id)) {
        firestoreUnreadIds.add(updated.id);
      }
    }

    if (firestoreUnreadIds.length == 1) {
      await FirestoreService.instance.inAppNotification.markRead(firestoreUnreadIds.first);
    } else if (firestoreUnreadIds.isNotEmpty) {
      await FirestoreService.instance.inAppNotification.markAllRead(firestoreUnreadIds);
    }
    if (updatedMatching.isNotEmpty) {
      await _persistAllRead(NotificationAudience.doctor, updatedMatching);
    }

    notifyListeners();
  }

  Future<void> markAllDoctorRead() async {
    var changed = false;
    final firestoreUnreadIds = <String>[];
    final updatedUnread = <AppNotification>[];

    for (var i = 0; i < _doctor.length; i++) {
      if (_doctor[i].isRead) continue;
      final updated = _doctor[i].copyWith(isRead: true);
      _doctor[i] = updated;
      changed = true;
      updatedUnread.add(updated);
      if (_doctorFirestoreIds.contains(updated.id)) {
        firestoreUnreadIds.add(updated.id);
      }
    }

    if (!changed) return;

    if (firestoreUnreadIds.isNotEmpty) {
      await FirestoreService.instance.inAppNotification.markAllRead(firestoreUnreadIds);
    }
    if (updatedUnread.isNotEmpty) {
      await _persistAllRead(NotificationAudience.doctor, updatedUnread);
    }
    notifyListeners();
  }

  Future<void> markPatientRead(String id) async {
    final index = _patient.indexWhere((n) => n.id == id);
    if (index < 0 || _patient[index].isRead) return;

    final readKey = _storageKey(_patient[index]);
    final matching = _patient.where((n) => !n.isRead && _storageKey(n) == readKey).toList();
    if (matching.isEmpty) return;

    final firestoreUnreadIds = <String>[];
    final updatedMatching = <AppNotification>[];

    for (final notification in matching) {
      final i = _patient.indexWhere((n) => n.id == notification.id);
      if (i < 0) continue;
      final updated = _patient[i].copyWith(isRead: true);
      _patient[i] = updated;
      updatedMatching.add(updated);
      if (_patientFirestoreIds.contains(updated.id)) {
        firestoreUnreadIds.add(updated.id);
      }
    }

    if (firestoreUnreadIds.length == 1) {
      await FirestoreService.instance.inAppNotification.markRead(firestoreUnreadIds.first);
    } else if (firestoreUnreadIds.isNotEmpty) {
      await FirestoreService.instance.inAppNotification.markAllRead(firestoreUnreadIds);
    }
    if (updatedMatching.isNotEmpty) {
      await _persistAllRead(NotificationAudience.patient, updatedMatching);
    }

    notifyListeners();
  }

  Future<void> markAllPatientRead() async {
    var changed = false;
    final firestoreUnreadIds = <String>[];
    final updatedUnread = <AppNotification>[];

    for (var i = 0; i < _patient.length; i++) {
      if (_patient[i].isRead) continue;
      final updated = _patient[i].copyWith(isRead: true);
      _patient[i] = updated;
      changed = true;
      updatedUnread.add(updated);
      if (_patientFirestoreIds.contains(updated.id)) {
        firestoreUnreadIds.add(updated.id);
      }
    }

    if (!changed) return;

    if (firestoreUnreadIds.isNotEmpty) {
      await FirestoreService.instance.inAppNotification.markAllRead(firestoreUnreadIds);
    }
    if (updatedUnread.isNotEmpty) {
      await _persistAllRead(NotificationAudience.patient, updatedUnread);
    }
    notifyListeners();
  }



  void handleDoctorAction(String actionKey, {String? targetId}) {

    switch (actionKey) {

      case 'mark_no_show':

        if (targetId != null) {

          addDoctor(DoctorNotificationEmitter.patientMarkedNoShow(targetId));

        }

      default:

        break;

    }

    notifyListeners();

  }



  void handlePatientAction(String actionKey, {String? targetId}) {

    switch (actionKey) {

      case 'mark_no_show':

      case 'join_now':

      case 'join_soon':

      case 'view_report':

      case 'view_prescription':

      case 'book_another':

      case 'track_phlebotomist':

      case 'log_vitals':

      case 'view_appointment':

      case 'accept_reschedule':

        break;

      default:

        break;

    }

    notifyListeners();

  }



  void seedDoctorWelcomeIfEmpty() {

    if (_doctor.isNotEmpty) return;

    addDoctor(DoctorNotificationEmitter.kycApproved());

  }

}

