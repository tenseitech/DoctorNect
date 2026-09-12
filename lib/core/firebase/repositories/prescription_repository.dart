import 'package:cloud_firestore/cloud_firestore.dart';



import '../../../features/doctor/clinical/models/clinical_models.dart';

import '../firestore_paths.dart';

import '../firebase_bootstrap.dart';

import '../firestore_query_limits.dart';

import '../firestore_read_helper.dart';

import '../mappers/prescription_firestore_mapper.dart';

import '../models/firestore_page.dart';

import 'patient_profile_repository.dart';



class PrescriptionRepository {

  PrescriptionRepository._();



  static final PrescriptionRepository instance = PrescriptionRepository._();



  Future<void> save(
    PrescriptionDraft draft,
    String doctorId, {
    bool isNewRecord = false,
  }) async {
    if (!FirebaseBootstrap.isReady) {
      throw StateError('Firebase is not available.');
    }
    if (doctorId.trim().isEmpty) {
      throw StateError('Doctor session is missing. Sign in again.');
    }

    final ref = FirebaseFirestore.instance
        .collection(FirestorePaths.prescriptions)
        .doc(draft.prescriptionId);

    final payload = <String, dynamic>{
      ...PrescriptionFirestoreMapper.toMap(draft, doctorId),
      'title': draft.primaryDiagnosis.trim().isEmpty
          ? 'Prescription — ${draft.patient.patientName}'
          : draft.primaryDiagnosis.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (isNewRecord) {
      payload['createdAt'] = FieldValue.serverTimestamp();
    }

    await ref.set(payload, SetOptions(merge: true));
  }



  /// One-time fetch (cache-first) for a doctor's recent prescriptions.

  Future<FirestorePage<PrescriptionDraft>> fetchForDoctor(

    String doctorId, {

    DocumentSnapshot<Map<String, dynamic>>? startAfter,

    int limit = FirestoreQueryLimits.prescriptionsPage,

    bool preferCache = true,

  }) {

    return _fetchPage(

      FirebaseFirestore.instance

          .collection(FirestorePaths.prescriptions)

          .where('doctorId', isEqualTo: doctorId)

          .orderBy('updatedAt', descending: true)

          .limit(limit),

      startAfter: startAfter,

      limit: limit,

      preferCache: preferCache,

      sortNewestFirst: true,

    );

  }



  /// One-time fetch (cache-first) for a patient's recent prescriptions.
  Future<FirestorePage<PrescriptionDraft>> fetchForPatient(
    String patientId, {
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = FirestoreQueryLimits.prescriptionsPage,
    bool preferCache = true,
  }) {
    return _fetchPage(
      FirebaseFirestore.instance
          .collection(FirestorePaths.prescriptions)
          .where('patientId', isEqualTo: patientId)
          .orderBy('updatedAt', descending: true)
          .limit(limit),
      startAfter: startAfter,
      limit: limit,
      preferCache: preferCache,
      sortNewestFirst: true,
    );
  }

  /// Doctor-facing fetch — empty when the patient has turned off sharing.
  Future<FirestorePage<PrescriptionDraft>> fetchForPatientForDoctor(
    String patientId, {
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int limit = FirestoreQueryLimits.prescriptionsPage,
    bool preferCache = true,
  }) async {
    if (!await PatientProfileRepository.instance.isPatientSharingClinicalDataWithDoctors(
      patientId,
      preferCache: preferCache,
    )) {
      return const FirestorePage(items: [], hasMore: false);
    }
    return fetchForPatient(
      patientId,
      startAfter: startAfter,
      limit: limit,
      preferCache: preferCache,
    );
  }

  /// Doctor-scoped fetch for one patient (matches Firestore security rules).
  Future<FirestorePage<PrescriptionDraft>> fetchForDoctorAndPatient(
    String doctorId,
    String patientId, {
    int limit = FirestoreQueryLimits.prescriptionsPage,
    bool preferCache = true,
  }) {
    return _fetchPage(
      FirebaseFirestore.instance
          .collection(FirestorePaths.prescriptions)
          .where('doctorId', isEqualTo: doctorId)
          .where('patientId', isEqualTo: patientId)
          .limit(limit),
      limit: limit,
      preferCache: preferCache,
      sortNewestFirst: true,
    );
  }

  /// Doctor-facing fetch — empty when the patient has turned off sharing.
  Future<FirestorePage<PrescriptionDraft>> fetchForDoctorAndPatientForDoctor(
    String doctorId,
    String patientId, {
    int limit = FirestoreQueryLimits.prescriptionsPage,
    bool preferCache = true,
  }) async {
    if (!await PatientProfileRepository.instance.isPatientSharingClinicalDataWithDoctors(
      patientId,
      preferCache: preferCache,
    )) {
      return const FirestorePage(items: [], hasMore: false);
    }
    return fetchForDoctorAndPatient(
      doctorId,
      patientId,
      limit: limit,
      preferCache: preferCache,
    );
  }



  Future<FirestorePage<PrescriptionDraft>> _fetchPage(

    Query<Map<String, dynamic>> baseQuery, {

    DocumentSnapshot<Map<String, dynamic>>? startAfter,

    required int limit,

    bool preferCache = true,

    bool sortNewestFirst = false,

  }) async {

    if (!FirebaseBootstrap.isReady) {

      return const FirestorePage(items: [], hasMore: false);

    }



    final query = startAfter == null ? baseQuery : baseQuery.startAfterDocument(startAfter);

    final snapshot = await FirestoreReadHelper.getQuery(query: query, preferCache: preferCache);

    var items = _mapPrescriptionDocs(snapshot.docs);

    if (sortNewestFirst) {
      items.sort((a, b) => b.prescriptionDate.compareTo(a.prescriptionDate));
    }



    return FirestorePage(

      items: items,

      lastDocument: snapshot.docs.isEmpty ? null : snapshot.docs.last,

      hasMore: snapshot.docs.length == limit,

    );

  }



  List<PrescriptionDraft> _mapPrescriptionDocs(

    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,

  ) {

    return docs

        .map((doc) => PrescriptionFirestoreMapper.fromMap(doc.data()))

        .whereType<PrescriptionDraft>()

        .toList();

  }

}


