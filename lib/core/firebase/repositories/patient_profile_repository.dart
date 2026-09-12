import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../features/patient/records/data/health_record_file_store.dart';
import '../../../features/patient/records/models/health_record_models.dart';
import '../firestore_paths.dart';
import '../firebase_bootstrap.dart';
import '../firestore_read_helper.dart';

class PatientProfileRepository {
  PatientProfileRepository._();

  static final PatientProfileRepository instance = PatientProfileRepository._();

  static final RegExp _registeredPatientId = RegExp(r'^p\d+$', caseSensitive: false);
  static final RegExp _walkInPatientId = RegExp(r'^wi\d+$', caseSensitive: false);

  static bool isRegisteredPatientId(String? patientId) =>
      patientId != null && patientId.isNotEmpty && _registeredPatientId.hasMatch(patientId);

  static bool isWalkInPatientId(String? patientId) =>
      patientId != null && patientId.isNotEmpty && _walkInPatientId.hasMatch(patientId);

  bool checkIsRegisteredPatientId(String? patientId) => isRegisteredPatientId(patientId);
  bool checkIsWalkInPatientId(String? patientId) => isWalkInPatientId(patientId);

  /// Patient opted in to share profile/health records with doctors (default true when unset).
  static bool sharesRecordsWithDoctors(Map<String, dynamic>? patientData) {
    if (patientData == null) return false;
    return patientData['shareRecordsWithDoctors'] as bool? ?? true;
  }

  /// Registered patients (`p*`) only — used for profile vault + health records.
  /// Walk-in ids have no persisted profile and cannot expose the vault.
  Future<bool> mayDoctorViewSharedPatientRecords(
    String patientId, {
    bool preferCache = true,
  }) async {
    if (!isRegisteredPatientId(patientId)) return false;
    return isPatientSharingClinicalDataWithDoctors(
      patientId,
      preferCache: preferCache,
    );
  }

  /// Whether doctors may read this patient's clinical history (RX, labs, visit notes).
  /// Walk-in / synthetic ids have no sharing preference — appointment-scoped data stays visible.
  Future<bool> isPatientSharingClinicalDataWithDoctors(
    String patientId, {
    bool preferCache = true,
  }) async {
    if (!isRegisteredPatientId(patientId)) return true;
    final data = await fetchPatientDocument(patientId, preferCache: preferCache);
    if (data == null) return false;
    return sharesRecordsWithDoctors(data);
  }

  Future<Map<String, dynamic>?> fetchPatientDocumentForDoctor(
    String patientId, {
    bool preferCache = true,
  }) async {
    if (!await mayDoctorViewSharedPatientRecords(patientId, preferCache: preferCache)) {
      return null;
    }
    return fetchPatientDocument(patientId, preferCache: preferCache);
  }

  Future<List<HealthRecord>> fetchHealthRecordsForDoctor(
    String patientId, {
    bool preferCache = true,
  }) async {
    if (!await mayDoctorViewSharedPatientRecords(patientId, preferCache: preferCache)) {
      return const [];
    }
    final records = await fetchHealthRecords(patientId);
    return records.where((record) => record.sharedWithDoctors).toList();
  }

  Future<Map<String, dynamic>?> fetchPatientDocument(
    String patientId, {
    bool preferCache = true,
  }) async {
    if (!FirebaseBootstrap.isReady) return null;
    try {
      final snap = await FirestoreReadHelper.getDocument(
        reference: FirebaseFirestore.instance.collection(FirestorePaths.patients).doc(patientId),
        preferCache: preferCache,
      );
      return snap.data();
    } catch (e) {
      return null;
    }
  }

  /// Records a patient↔doctor relationship for rules-side care-team grant checks.
  /// Walk-in (`wi*`) patients have no registered profile and skip this path.
  Future<bool> ensureDoctorPatientLink({
    required String patientId,
    required String doctorId,
    required String source,
    String? fromDoctorId,
    String? referralId,
  }) async {
    if (!FirebaseBootstrap.isReady || patientId.isEmpty || doctorId.isEmpty) return false;
    if (!isRegisteredPatientId(patientId)) return false;

    final payload = <String, dynamic>{
      'doctorId': doctorId,
      'source': source,
      'createdAt': FieldValue.serverTimestamp(),
      if (fromDoctorId != null && fromDoctorId.isNotEmpty) 'fromDoctorId': fromDoctorId,
      if (referralId != null && referralId.isNotEmpty) 'referralId': referralId,
    };

    try {
      await FirebaseFirestore.instance
          .collection(FirestorePaths.patients)
          .doc(patientId)
          .collection('doctor_links')
          .doc(doctorId)
          .set(payload, SetOptions(merge: true));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> grantDoctorCareTeamAccess({
    required String patientId,
    required String doctorId,
  }) async {
    if (!FirebaseBootstrap.isReady || patientId.isEmpty || doctorId.isEmpty) return false;
    if (isWalkInPatientId(patientId)) return false;
    if (!isRegisteredPatientId(patientId)) return false;
    try {
      await FirebaseFirestore.instance.collection(FirestorePaths.patients).doc(patientId).set(
        {
          'careTeamDoctorIds': FieldValue.arrayUnion([doctorId]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> savePatientDocument(String patientId, Map<String, dynamic> data) async {
    if (!FirebaseBootstrap.isReady) return;
    await FirebaseFirestore.instance.collection(FirestorePaths.patients).doc(patientId).set(
      {
        ...data,
        'patientId': patientId,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<List<HealthRecord>> fetchHealthRecords(String patientId) async {
    if (!FirebaseBootstrap.isReady) return const [];

    try {
      final snapshot = await FirestoreReadHelper.getQuery(
        query: FirebaseFirestore.instance
            .collection(FirestorePaths.healthRecords)
            .where('patientId', isEqualTo: patientId)
            .limit(50),
      );

      final records = snapshot.docs.map((doc) {
        final data = doc.data();
        final storageStatus = data['fileStorage'] as String?;
        return HealthRecord(
          id: doc.id,
          title: data['title'] as String? ?? 'Record',
          type: HealthRecordType.values.byName(data['type'] as String? ?? 'other'),
          date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
          source: RecordSource.values.byName(data['source'] as String? ?? 'selfUploaded'),
          fileName: data['fileName'] as String? ?? '',
          doctorName: data['doctorName'] as String?,
          labName: data['labName'] as String?,
          isImage: data['isImage'] as bool? ?? false,
          notes: data['notes'] as String?,
          sharedWithDoctors: data['sharedWithDoctors'] as bool? ?? false,
          fileStorage: storageStatus != null
              ? HealthRecordFileStorage.values.byName(storageStatus)
              : HealthRecordFileStorage.none,
          storageUrl: data['storageUrl'] as String?,
        );
      }).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      return records;
    } catch (e) {
      rethrow; // FIXED: surface fetch failures to callers instead of returning an empty list
    }
  }

  Future<void> savePatientFcmToken(String patientId, String token) async {
    if (!FirebaseBootstrap.isReady || patientId.isEmpty || token.isEmpty) return;
    await FirebaseFirestore.instance.collection(FirestorePaths.patients).doc(patientId).set(
      {
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> clearPatientFcmToken(String patientId) async {
    if (!FirebaseBootstrap.isReady || patientId.isEmpty) return;
    await FirebaseFirestore.instance.collection(FirestorePaths.patients).doc(patientId).set(
      {
        'fcmToken': FieldValue.delete(),
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> saveHealthRecord(String patientId, HealthRecord record) async {
    if (!FirebaseBootstrap.isReady) return;
    await FirebaseFirestore.instance.collection(FirestorePaths.healthRecords).doc(record.id).set({
      'patientId': patientId,
      'title': record.title,
      'type': record.type.name,
      'date': Timestamp.fromDate(record.date),
      'source': record.source.name,
      'fileName': record.fileName,
      if (record.doctorName != null) 'doctorName': record.doctorName,
      if (record.labName != null) 'labName': record.labName,
      'isImage': record.isImage,
      if (record.notes != null) 'notes': record.notes,
      'sharedWithDoctors': record.sharedWithDoctors,
      if (record.fileStorage != HealthRecordFileStorage.none)
        'fileStorage': record.fileStorage.name,
      if (record.storageUrl != null) 'storageUrl': record.storageUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteHealthRecord(String recordId) async {
    if (!FirebaseBootstrap.isReady || recordId.isEmpty) return;

    final ref = FirebaseFirestore.instance.collection(FirestorePaths.healthRecords).doc(recordId);
    final snap = await ref.get();
    final data = snap.data();
    if (data != null) {
      final patientId = data['patientId'] as String? ?? '';
      final fileName = data['fileName'] as String? ?? '';
      if (patientId.isNotEmpty && fileName.isNotEmpty) {
        await HealthRecordFileStore.deleteRecordFiles(
          patientId: patientId,
          recordId: recordId,
          fileName: fileName,
        );
      }
    }

    await ref.delete();
  }
}
