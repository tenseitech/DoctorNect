import '../../../../core/firebase/firestore_service.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/firebase/firebase_bootstrap.dart';
import '../../../../core/firebase/firestore_paths.dart';
import '../../../../core/supabase/supabase_bootstrap.dart';
import '../../../../core/supabase/supabase_patient_repository.dart';
import '../../../../core/notifications/in_app_notification_service.dart';
import '../../../../core/session/patient_session.dart';
import '../../../doctor/clinical/models/clinical_models.dart';
import '../../data/patient_favorites_store.dart';
import '../models/patient_profile_models.dart';

class MockNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

class PatientProfileMock {
  static final MockNotifier _notifier = MockNotifier();
  static bool hasDismissedCompletionDialog = false;

  static int get profileCompletionPercentage {
    int total = 0;
    int completed = 0;

    void check(bool isComplete) {
      total++;
      if (isComplete) completed++;
    }

    check(profile.name.isNotEmpty);
    check(profile.age > 0);
    check(profile.gender.isNotEmpty);
    check(profile.mobile.isNotEmpty);
    check(profile.bloodGroup.isNotEmpty);

    check(profileAddress.country.isNotEmpty);
    check(profileAddress.state.isNotEmpty);
    check(profileAddress.city.isNotEmpty);
    check(profileAddress.addressLine1.isNotEmpty);
    check(profileAddress.pincode.isNotEmpty);

    if (total == 0) return 0;
    return ((completed / total) * 100).round();
  }

  static Listenable get listenable => _notifier;

  static void notifyProfileUpdated() => _notifier.notify();

  static final profile = PatientProfile(
    name: '',
    age: 0,
    gender: '',
    bloodGroup: '',
    mobile: '',
    email: '',
    photoInitial: 'P',
  );

  static String profileCity = '';
  static PatientAddress profileAddress = const PatientAddress();
  static String? invitedDoctorId;
  static List<String> conditions = [];
  static List<String> allergies = [];
  static final vaccinations = <({String name, DateTime date})>[];
  static List<FamilyProfileMember> familyMembers = [];
  static final Map<String, List<PatientPrescription>>
      _prescriptionsByPatientKey = {};

  static String? _notificationPrefsLoadedForPatientId;
  static Future<void>? _notificationPrefsLoadFuture;

  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _patientSub;

  static void reset() {
    _patientSub?.cancel();
    _patientSub = null;
    profile.name = '';
    profile.age = 0;
    profile.gender = '';
    profile.bloodGroup = '';
    profile.mobile = '';
    profile.email = '';
    profile.photoInitial = 'P';
    profile.photoUrl = null;
    profile.height = 0;
    profile.weight = 0;
    profileCity = '';
    profileAddress = const PatientAddress();
    invitedDoctorId = null;
    conditions = [];
    allergies = [];
    vaccinations.clear();
    familyMembers = [];
    _prescriptionsByPatientKey.clear();
    hasDismissedCompletionDialog = false;
    resetNotificationPrefsSession();
    notifyProfileUpdated();
  }

  static void resetNotificationPrefsSession() {
    _notificationPrefsLoadedForPatientId = null;
    _notificationPrefsLoadFuture = null;
  }

  /// Loads notification prefs from Firestore before inbox sync applies filters.
  static Future<void> ensureNotificationPrefsLoaded(String patientId) async {
    if (patientId.isEmpty) return;
    if (_notificationPrefsLoadedForPatientId == patientId) return;
    _notificationPrefsLoadFuture ??= _loadNotificationPrefs(patientId);
    await _notificationPrefsLoadFuture;
  }

  static Future<void> _loadNotificationPrefs(String patientId) async {
    try {
      final data =
          await FirestoreService.instance.patientProfile.fetchPatientDocument(
        patientId,
        preferCache: false,
      );
      final prefs = data?['notificationPrefs'] as Map<String, dynamic>?;
      if (prefs != null) {
        _applyNotificationPrefs(prefs);
      }
      _notificationPrefsLoadedForPatientId = patientId;
    } finally {
      _notificationPrefsLoadFuture = null;
    }
  }

  /// Applies remote notification prefs and re-filters the inbox (e.g. Firestore console edits).
  static void applyNotificationPrefsFromFirestore(Map<String, dynamic> prefs) {
    _applyNotificationPrefs(prefs);
    InAppNotificationService.instance.onPatientNotificationPrefsChanged();
  }

  static void listenToPatientDocument(String patientId) {
    if (patientId.isEmpty || !FirebaseBootstrap.isReady) return;
    _patientSub?.cancel();
    _patientSub = FirebaseFirestore.instance
        .collection(FirestorePaths.patients)
        .doc(patientId)
        .snapshots()
        .listen((snap) {
      if (!snap.exists || snap.data() == null) return;
      final data = snap.data()!;
      final url =
          (data['photoUrl'] as String?) ?? (data['photoURL'] as String?);
      if (url != profile.photoUrl) {
        profile.photoUrl = url;
        notifyProfileUpdated();
      }
    });
  }

  static void _applyFromSupabase(Map<String, dynamic> data) {
    profile.name = data['name'] as String? ?? profile.name;
    profile.age = (data['age'] as num?)?.toInt() ?? profile.age;
    profile.gender = data['gender'] as String? ?? profile.gender;
    profile.mobile = data['mobile'] as String? ?? profile.mobile;
    profile.email = data['email'] as String? ?? profile.email;
    profile.bloodGroup = data['blood_group'] as String? ?? profile.bloodGroup;
    if (data['height'] != null) {
      profile.height = double.tryParse(data['height'].toString()) ?? profile.height;
    }
    if (data['weight'] != null) {
      profile.weight = double.tryParse(data['weight'].toString()) ?? profile.weight;
    }
    profile.photoInitial =
        profile.name.isNotEmpty ? profile.name[0].toUpperCase() : 'P';
    profile.photoUrl = (data['photo_url'] as String?) ?? profile.photoUrl;

    profileAddress = PatientAddress(
      city: data['city'] as String? ?? '',
      state: data['state'] as String? ?? '',
      pincode: data['pincode'] as String? ?? '',
      country: data['country'] as String? ?? 'India',
      addressLine1: data['address'] as String? ?? '',
    );
    profileCity = profileAddress.city;

    if (data['conditions'] is List) {
      conditions = (data['conditions'] as List).map((e) => e.toString()).toList();
    }
    if (data['allergies'] is List) {
      allergies = (data['allergies'] as List).map((e) => e.toString()).toList();
    }
    privacyPrefs.shareRecordsWithDoctors =
        data['share_records_with_doctors'] as bool? ?? true;
  }

  static Future<void> loadFromFirestore(String patientId) async {
    listenToPatientDocument(patientId);

    if (SupabaseBootstrap.isReady) {
      try {
        final supaData = await SupabasePatientRepository.instance.fetchProfile(patientId);
        if (supaData != null) {
          _applyFromSupabase(supaData);
          notifyProfileUpdated();
          return;
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Failed to load profile from Supabase: $e');
      }
    }

    final data = await FirestoreService.instance.patientProfile
        .fetchPatientDocument(patientId);
    if (data == null) return;

    profile.name = data['name'] as String? ?? profile.name;
    profile.age = (data['age'] as num?)?.toInt() ?? profile.age;
    profile.gender = data['gender'] as String? ?? profile.gender;
    profile.mobile = data['mobile'] as String? ?? profile.mobile;
    profile.email = data['email'] as String? ?? profile.email;
    profile.bloodGroup = data['bloodGroup'] as String? ?? profile.bloodGroup;
    profile.height = (data['height'] as num?)?.toDouble() ?? profile.height;
    profile.weight = (data['weight'] as num?)?.toDouble() ?? profile.weight;
    profile.photoInitial =
        profile.name.isNotEmpty ? profile.name[0].toUpperCase() : 'P';
    profile.photoUrl = (data['photoUrl'] as String?) ??
        (data['photoURL'] as String?) ??
        profile.photoUrl;
    profileAddress = PatientAddress.fromMap(data);
    if (!profileAddress.hasContent) {
      final city = data['city'] as String? ?? '';
      final pincode = data['pincode'] as String? ?? '';
      if (city.isNotEmpty || pincode.isNotEmpty) {
        profileAddress = PatientAddress(city: city, pincode: pincode);
      }
    }
    profileCity = profileAddress.city.isNotEmpty
        ? profileAddress.city
        : data['city'] as String? ?? '';

    conditions =
        (data['conditions'] as List<dynamic>? ?? const []).cast<String>();
    allergies =
        (data['allergies'] as List<dynamic>? ?? const []).cast<String>();

    final prefs = data['notificationPrefs'] as Map<String, dynamic>?;
    if (prefs != null) _applyNotificationPrefs(prefs);

    privacyPrefs.shareRecordsWithDoctors =
        data['shareRecordsWithDoctors'] as bool? ?? true;
    privacyPrefs.allowHealthInsights =
        data['allowHealthInsights'] as bool? ?? false;
    privacyPrefs.twoFactorEnabled = data['twoFactorEnabled'] as bool? ?? false;

    familyMembers =
        await FirestoreService.instance.familyMember.fetchForPatient(patientId);
    PatientFavoritesStore.instance.applyFromPatientData(data);
    notifyProfileUpdated();
  }

  static Future<void> updateProfileCity(String city) async {
    profileCity = city;
    profileAddress = profileAddress.copyWith(city: city);
    notifyProfileUpdated();
    await persistCurrentProfile();
  }

  static Future<void> updateProfileAddress(PatientAddress address) async {
    profileAddress = address;
    profileCity = address.city;
    notifyProfileUpdated();
    await persistCurrentProfile();
  }

  static void _applyNotificationPrefs(Map<String, dynamic> prefs) {
    final p = notificationPrefs;
    p.appointmentReminders =
        prefs['appointmentReminders'] as bool? ?? p.appointmentReminders;
    p.reminderTiming = ReminderTiming.values.byName(
      prefs['reminderTiming'] as String? ?? p.reminderTiming.name,
    );
    p.medicationReminders =
        prefs['medicationReminders'] as bool? ?? p.medicationReminders;
    p.labReportAlert = prefs['labReportAlert'] as bool? ?? p.labReportAlert;
    p.healthTips = prefs['healthTips'] as bool? ?? p.healthTips;
    p.offers = prefs['offers'] as bool? ?? p.offers;
    p.channelApp = prefs['channelApp'] as bool? ?? p.channelApp;
    p.channelSms = prefs['channelSms'] as bool? ?? p.channelSms;
    p.channelEmail = prefs['channelEmail'] as bool? ?? p.channelEmail;
    p.channelWhatsapp = prefs['channelWhatsapp'] as bool? ?? p.channelWhatsapp;
    final meds = prefs['medications'] as List<dynamic>? ?? const [];
    p.medications = meds.map((item) {
      final map = item as Map<String, dynamic>;
      return MedicationReminder(
        name: map['name'] as String? ?? '',
        morningTime: map['morningTime'] as String?,
        afternoonTime: map['afternoonTime'] as String?,
        eveningTime: map['eveningTime'] as String?,
        nightTime: map['nightTime'] as String?,
      );
    }).toList();
  }

  static Map<String, dynamic> _notificationPrefsMap() {
    final p = notificationPrefs;
    return {
      'appointmentReminders': p.appointmentReminders,
      'reminderTiming': p.reminderTiming.name,
      'medicationReminders': p.medicationReminders,
      'medications': p.medications
          .map((m) => {
                'name': m.name,
                if (m.morningTime != null) 'morningTime': m.morningTime,
                if (m.afternoonTime != null) 'afternoonTime': m.afternoonTime,
                if (m.eveningTime != null) 'eveningTime': m.eveningTime,
                if (m.nightTime != null) 'nightTime': m.nightTime,
              })
          .toList(),
      'labReportAlert': p.labReportAlert,
      'healthTips': p.healthTips,
      'offers': p.offers,
      'channelApp': p.channelApp,
      'channelSms': p.channelSms,
      'channelEmail': p.channelEmail,
      'channelWhatsapp': p.channelWhatsapp,
    };
  }

  static Future<void> persistCurrentProfile() async {
    final id = PatientSession.loggedInPatientId;
    if (id.isEmpty) return;
    await persistProfile(id);
  }

  static Future<void> addFamilyMember(FamilyProfileMember member) async {
    final id = PatientSession.loggedInPatientId;
    if (id.isEmpty) return;
    await FirestoreService.instance.familyMember.saveMember(id, member);
    familyMembers = [...familyMembers, member];
  }

  static Future<void> updateFamilyMember(FamilyProfileMember member) async {
    final id = PatientSession.loggedInPatientId;
    if (id.isEmpty) return;
    await FirestoreService.instance.familyMember.saveMember(id, member);
    final index = familyMembers.indexWhere((m) => m.id == member.id);
    if (index >= 0) {
      familyMembers[index] = member;
    }
  }

  static Future<void> removeFamilyMember(String memberId) async {
    final id = PatientSession.loggedInPatientId;
    if (id.isNotEmpty) {
      await FirestoreService.instance.familyMember.deleteMember(memberId);
    }
    familyMembers = familyMembers.where((m) => m.id != memberId).toList();
    notifyProfileUpdated();
  }

  static Future<void> persistProfile(String patientId) async {
    if (SupabaseBootstrap.isReady) {
      final supaFields = {
        'name': profile.name,
        'age': profile.age,
        'gender': profile.gender,
        'mobile': profile.mobile,
        'email': profile.email,
        'blood_group': profile.bloodGroup,
        'height': profile.height > 0 ? profile.height.toString() : null,
        'weight': profile.weight > 0 ? profile.weight.toString() : null,
        'photo_url': profile.photoUrl,
        'address': profileAddress.addressLine1.isNotEmpty
            ? profileAddress.addressLine1
            : profileAddress.fullLabel,
        'city':
            profileAddress.city.isNotEmpty ? profileAddress.city : profileCity,
        'state': profileAddress.state,
        'pincode': profileAddress.pincode,
        'country': profileAddress.country.isNotEmpty
            ? profileAddress.country
            : 'India',
        'conditions': conditions,
        'allergies': allergies,
        'share_records_with_doctors': privacyPrefs.shareRecordsWithDoctors,
        'profile_completed': true,
      };

      await SupabasePatientRepository.instance.updateProfile(
        context: null,
        patientId: patientId,
        fields: supaFields,
      );
    }

    if (FirebaseBootstrap.isReady) {
      await FirestoreService.instance.patientProfile
          .savePatientDocument(patientId, {
        'name': profile.name,
        'age': profile.age,
        'gender': profile.gender,
        'mobile': profile.mobile,
        'email': profile.email,
        'bloodGroup': profile.bloodGroup,
        'height': profile.height,
        'weight': profile.weight,
        'photoUrl': profile.photoUrl,
        'city':
            profileAddress.city.isNotEmpty ? profileAddress.city : profileCity,
        'country': profileAddress.country,
        'addressLine1': profileAddress.addressLine1,
        'addressLine2': profileAddress.addressLine2,
        'state': profileAddress.state,
        'pincode': profileAddress.pincode,
        'landmark': profileAddress.landmark,
        'conditions': conditions,
        'allergies': allergies,
        'notificationPrefs': _notificationPrefsMap(),
        'shareRecordsWithDoctors': privacyPrefs.shareRecordsWithDoctors,
        'allowHealthInsights': privacyPrefs.allowHealthInsights,
        'twoFactorEnabled': privacyPrefs.twoFactorEnabled,
        'hiddenDoctorIds':
            PatientFavoritesStore.instance.hiddenDoctorIds.toList(),
        'hiddenLabKeys': PatientFavoritesStore.instance.hiddenLabKeys.toList(),
        'addedDoctorIds': PatientFavoritesStore.instance.addedDoctorIds,
        'addedDoctors': PatientFavoritesStore.instance.addedDoctorsForPersist,
        'addedLabs': PatientFavoritesStore.instance.addedLabs
            .map((lab) => lab.toMap())
            .toList(),
        if (invitedDoctorId != null && invitedDoctorId!.isNotEmpty)
          'invitedDoctorId': invitedDoctorId,
        if (invitedDoctorId != null && invitedDoctorId!.isNotEmpty)
          'primaryDoctorId': invitedDoctorId,
      });
    }
  }

  static void applyRegistration({
    required String id,
    required String name,
    required int age,
    required String gender,
    required String mobile,
    required String email,
    required String city,
    String? state,
    String? country,
    String? invitedDoctorId,
  }) {
    profile.name = name;
    profile.age = age;
    profile.gender = gender;
    profile.mobile = mobile;
    profile.email = email;
    profile.photoInitial = name.isNotEmpty ? name[0].toUpperCase() : 'P';
    profileCity = city;
    profileAddress = PatientAddress(
      city: city,
      state: state ?? '',
      country: country ?? '',
    );
    PatientProfileMock.invitedDoctorId = invitedDoctorId;
    PatientSession.setPatient(id: id, name: name);
    _prescriptionsByPatientKey.putIfAbsent(name.trim().toLowerCase(), () => []);
    notifyProfileUpdated();
    unawaited(persistProfile(id));
  }

  static String _patientKey(PatientClinicalContext patient) {
    if (patient.patientId != null && patient.patientId!.isNotEmpty) {
      return patient.patientId!.trim().toLowerCase();
    }
    return patient.patientName.trim().toLowerCase();
  }

  static List<PatientPrescription> _currentPrescriptions() {
    final key = PatientSession.patientKey;
    final list = _prescriptionsByPatientKey[key];
    if (list == null) return [];
    return List<PatientPrescription>.from(list);
  }

  static List<PatientPrescription> prescriptions() {
    final now = DateTime.now();
    return _currentPrescriptions()
        .map(
          (p) => PatientPrescription(
            id: p.id,
            title: p.title,
            doctorName: p.doctorName,
            date: p.prescriptionId != null
                ? p.date
                : p.id == 'rx1'
                    ? now.subtract(const Duration(days: 10))
                    : p.id == 'rx2'
                        ? now.subtract(const Duration(days: 28))
                        : p.date,
            fileName: p.fileName,
            prescriptionId: p.prescriptionId,
          ),
        )
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  static void syncPrescriptionFromDraft(
    PrescriptionDraft draft, {
    required String doctorName,
  }) {
    final key = _patientKey(draft.patient);
    final name = doctorName.startsWith('Dr.') ? doctorName : 'Dr. $doctorName';
    final title = draft.primaryDiagnosis.trim().isEmpty
        ? 'Prescription — ${draft.patient.patientName}'
        : draft.primaryDiagnosis.trim();

    final list = _prescriptionsByPatientKey.putIfAbsent(
        key, () => <PatientPrescription>[]);
    list.removeWhere((p) => p.prescriptionId == draft.prescriptionId);
    list.insert(
      0,
      PatientPrescription(
        id: draft.prescriptionId,
        prescriptionId: draft.prescriptionId,
        title: title,
        doctorName: name,
        date: draft.prescriptionDate,
        fileName: '${draft.prescriptionId}.pdf',
      ),
    );
  }

  @Deprecated('Use ClinicalPrescriptionStore.save + syncPrescriptionFromDraft')
  static void addPrescription({
    required String title,
    required String doctorName,
  }) {
    final name = doctorName.startsWith('Dr.') ? doctorName : 'Dr. $doctorName';
    final list = _prescriptionsByPatientKey.putIfAbsent(
        PatientSession.patientKey, () => <PatientPrescription>[]);
    list.insert(
      0,
      PatientPrescription(
        id: 'rx${DateTime.now().millisecondsSinceEpoch}',
        title: title,
        doctorName: name,
        date: DateTime.now(),
        fileName: 'prescription_${DateTime.now().millisecondsSinceEpoch}.pdf',
      ),
    );
  }

  static final notificationPrefs = NotificationPrefs();

  static final privacyPrefs = PrivacyPrefs();

  static const faqs = [
    FaqItem(
      question: 'How do I reschedule an appointment?',
      answer:
          'Open Appointments → Upcoming → tap Reschedule on your booking, or contact the clinic directly.',
    ),
    FaqItem(
      question: 'When will I receive my lab report?',
      answer:
          'Most lab partners upload reports within 24–48 hours. You will get an app notification when ready.',
    ),
    FaqItem(
      question: 'Can I share records with my doctor?',
      answer:
          'Yes. From Health Records, tap Share and select doctors you trust.',
    ),
  ];

  static const supportPhone = '+91 1800 123 4567';
  static const supportWhatsApp = '+91 98765 43210';
  static const supportEmail = 'support@doctornect.com';
  static const websiteUrl = 'https://doctornect.com';
  static const appDownloadUrl = 'https://doctornect.com/download';
  static const appVersion = '1.0.1';
}
