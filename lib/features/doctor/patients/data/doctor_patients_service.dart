import '../../../../core/firebase/firestore_service.dart';
import 'package:intl/intl.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/data/shared_appointments_store.dart';
import '../../../../core/session/doctor_session.dart';
import '../../clinical/data/clinical_prescription_store.dart';
import '../../clinical/models/clinical_models.dart';
import '../../models/doctor_models.dart';
import 'package:medibond/features/patient/models/patient_models.dart';
import '../../../patient/appointments/models/patient_appointment_models.dart';

/// Builds doctor-facing patient lists from real appointment records.
abstract final class DoctorPatientsService {
  static final List<DoctorPatientSummary> _registeredPatientsCache = [];

  static void clearCache() {
    _registeredPatientsCache.clear();
  }

  /// Refreshes appointment records when the doctor opens the Patients tab.
  static Future<void> refreshOnTabOpen({bool force = false}) async {
    final doctorId = DoctorSession.loggedInDoctorId;
    if (doctorId.isEmpty) return;
    await SharedAppointmentsStore.instance.refreshForDoctor(
      doctorId,
      preferCache: true,
      force: force,
    );
  }

  static String patientGroupKey(DoctorNectAppointmentRecord record) {
    final patientId = record.patientId?.trim();
    if (patientId != null && patientId.isNotEmpty) return patientId;

    final name = record.patientName.trim().toLowerCase();
    final digits = (record.contactNumber ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (name.isNotEmpty && digits.length >= 10) {
      return 'phone_${digits.substring(digits.length - 10)}';
    }
    if (name.isNotEmpty) {
      return 'name_${name}_${record.patientAge}_'
          '${AppConstants.normalizePatientGender(record.patientGender)}';
    }
    return 'fallback_${record.id}';
  }

  static List<DoctorNectAppointmentRecord> _recordsForDoctor(String doctorId) {
    return SharedAppointmentsStore.instance.records
        .where((r) => r.doctorId == doctorId)
        .toList();
  }

  static List<DoctorPatientSummary> summariesForDoctor(String doctorId) {
    final records = _recordsForDoctor(doctorId);

    final grouped = <String, List<DoctorNectAppointmentRecord>>{};
    for (final record in records) {
      final key = patientGroupKey(record);
      grouped.putIfAbsent(key, () => []).add(record);
    }

    final dynamicSummaries = grouped.entries.map((entry) {
      final visits = entry.value..sort((a, b) => b.dateTime.compareTo(a.dateTime));
      final latest = visits.first;
      final activeVisits = visits.where((v) => !v.isCancelled).toList();
      final referenceVisits = activeVisits.isNotEmpty ? activeVisits : visits;

      final cached = _registeredPatientsCache.where((s) => s.id == entry.key).firstOrNull;

      return DoctorPatientSummary(
        id: entry.key,
        name: cached?.name ?? latest.patientName,
        age: cached?.age ?? latest.patientAge,
        gender: cached?.gender ??
            AppConstants.normalizePatientGender(latest.patientGender),
        mobile: cached?.mobile ?? _bestMobile(visits),
        lastVisitDate: referenceVisits.first.dateTime,
        totalVisits: visits.length,
        conditions: const [],
        isNew: referenceVisits.length == 1 &&
            referenceVisits.every((v) => v.visitType == AppointmentType.newVisit),
        isFollowUp: referenceVisits.any((v) => v.visitType == AppointmentType.followUp),
      );
    }).toList();

    final existingIds = dynamicSummaries.map((s) => s.id).toSet();
    final existingNames = dynamicSummaries.map((s) => s.name.toLowerCase().trim()).toSet();

    final otherRegistered = _registeredPatientsCache.where((s) =>
        !existingIds.contains(s.id) &&
        !existingNames.contains(s.name.toLowerCase().trim()),
    ).toList();

    return [...dynamicSummaries, ...otherRegistered];
  }

  static String _bestMobile(List<DoctorNectAppointmentRecord> visits) {
    for (final visit in visits) {
      final mobile = visit.contactNumber?.trim();
      if (mobile != null && mobile.isNotEmpty) return mobile;
    }
    return '';
  }

  static List<MedicationRecord> _currentMedicationsFromPrescriptions(
    List<PrescriptionDraft> prescriptions,
  ) {
    final seen = <String>{};
    final medications = <MedicationRecord>[];

    for (final rx in prescriptions) {
      for (final medicine in rx.validMedicines) {
        final key = medicine.name.trim().toLowerCase();
        if (key.isEmpty || !seen.add(key)) continue;

        final dosage = medicine.dosageLabel.trim();
        medications.add(
          MedicationRecord(
            name: medicine.name.trim(),
            dosage: dosage.isEmpty ? '—' : dosage,
          ),
        );
      }
    }

    medications.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return medications;
  }

  static String? _registeredIdFromKey(String patientKey) {
    if (PatientProfileRepository.isRegisteredPatientId(patientKey)) return patientKey;

    final resolved = resolveRealPatientId(patientKey);
    if (PatientProfileRepository.isRegisteredPatientId(resolved)) return resolved;

    final doctorId = DoctorSession.loggedInDoctorId;
    for (final record in SharedAppointmentsStore.instance.records) {
      if (doctorId.isNotEmpty && record.doctorId != doctorId) continue;
      if (patientGroupKey(record) != patientKey) continue;
      if (PatientProfileRepository.isRegisteredPatientId(record.patientId)) {
        return record.patientId;
      }
    }

    return null;
  }

  static Future<bool> canViewClinicalHistoryForKey(String patientKey) async {
    final registeredId = _registeredIdFromKey(patientKey);
    if (registeredId == null) return true;
    return FirestoreService.instance.patientProfile.isPatientSharingClinicalDataWithDoctors(
      registeredId,
    );
  }

  static Future<DoctorPatientProfile?> profileFor(String patientKey, {String? doctorId}) async {
    final docId = doctorId ?? DoctorSession.loggedInDoctorId;
    final records = SharedAppointmentsStore.instance.records
        .where((r) {
          if (r.doctorId != docId) return false;
          return patientGroupKey(r) == patientKey;
        })
        .toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

    if (records.isEmpty) {
      final cached = _registeredPatientsCache.where((s) => s.id == patientKey).firstOrNull;
      if (cached == null) return null;

      final dummyRecord = DoctorNectAppointmentRecord(
        id: '',
        appointmentId: '',
        doctorId: docId,
        doctorName: '',
        specialization: '',
        patientName: cached.name,
        patientAge: cached.age,
        patientGender: cached.gender,
        dateTime: DateTime.now(),
        slotLabel: '',
        tokenNumber: 0,
        visitType: AppointmentType.newVisit,
        patientStatus: PatientBookingStatus.confirmed,
        doctorStatus: AppointmentStatus.confirmed,
        patientId: patientKey,
        contactNumber: cached.mobile,
      );

      final demographics = await _loadDemographics([dummyRecord], dummyRecord);

      return DoctorPatientProfile(
        summary: cached,
        dateOfBirth: demographics.dateOfBirth ?? DateTime(DateTime.now().year - cached.age, 1, 1),
        bloodGroup: demographics.bloodGroup,
        email: demographics.email,
        emergencyContact: demographics.emergencyContact,
        insurance: demographics.insurance,
        knownConditions: demographics.knownConditions,
        allergies: demographics.allergies,
        surgeries: demographics.surgeries,
        familyHistory: demographics.familyHistory,
        currentMedications: const [],
        vaccinations: const [],
        visits: const [],
        files: const [],
      );
    }

    final latest = records.first;
    final summary = DoctorPatientSummary(
      id: patientKey,
      name: latest.patientName,
      age: latest.patientAge,
      gender: AppConstants.normalizePatientGender(latest.patientGender),
      mobile: latest.contactNumber ?? '',
      lastVisitDate: latest.dateTime,
      totalVisits: records.length,
      conditions: const [],
      isNew: records.length == 1 &&
          records.every((v) => v.visitType == AppointmentType.newVisit),
      isFollowUp: records.any((v) => v.visitType == AppointmentType.followUp),
    );

    final visits = records
        .map(
          (r) => VisitRecord(
            id: r.id,
            date: r.dateTime,
            diagnosis: r.diagnosis ??
                (r.chiefComplaints.isNotEmpty ? r.chiefComplaintsLabel : 'Consultation'),
            chiefComplaints: r.chiefComplaints,
            observations: r.observations,
            symptoms: r.symptoms,
            hasPrescription: r.hasPrescription,
            hasLabReports: r.hasReport || r.labReports.isNotEmpty,
            status: r.doctorStatus,
          ),
        )
        .toList();

    final canViewClinicalHistory = await canViewClinicalHistoryForKey(patientKey);

    final cachedPrescriptions = canViewClinicalHistory
        ? ClinicalPrescriptionStore.instance.forPatient(patientKey)
        : const <PrescriptionDraft>[];
    final files = cachedPrescriptions
        .map(
          (p) => PatientFile(
            id: p.prescriptionId,
            name: p.primaryDiagnosis.trim().isNotEmpty
                ? 'Prescription · ${p.primaryDiagnosis.trim()}'
                : 'Prescription · ${DateFormat('dd MMM yyyy').format(p.prescriptionDate)}',
            type: PatientFileType.prescription,
            date: p.prescriptionDate,
          ),
        )
        .toList();

    final demographics = await _loadDemographics(records, latest);

    return DoctorPatientProfile(
      summary: summary,
      dateOfBirth: demographics.dateOfBirth ?? DateTime(DateTime.now().year - latest.patientAge, 1, 1),
      bloodGroup: demographics.bloodGroup,
      email: demographics.email,
      emergencyContact: demographics.emergencyContact,
      insurance: demographics.insurance,
      knownConditions: demographics.knownConditions,
      allergies: demographics.allergies,
      surgeries: demographics.surgeries,
      familyHistory: demographics.familyHistory,
      currentMedications: const [],
      vaccinations: const [],
      visits: canViewClinicalHistory ? visits : const [],
      files: canViewClinicalHistory ? files : const [],
    );
  }

  static bool _isFirestorePatientId(String? id) {
    if (id == null || id.isEmpty) return false;
    // FIXED: also match walk-in ids (e.g. "wi17012...") so their demographics get fetched too.
    return RegExp(r'^p\d+$').hasMatch(id) || RegExp(r'^wi', caseSensitive: false).hasMatch(id);
  }

  static String resolveRealPatientId(String key) {
    if (_isFirestorePatientId(key)) return key;

    // Try resolving from cache by phone or name
    if (key.startsWith('phone_')) {
      final phone = key.substring('phone_'.length);
      final match = _registeredPatientsCache.where((s) {
        final digits = s.mobile.replaceAll(RegExp(r'\D'), '');
        return digits.endsWith(phone) || phone.endsWith(digits);
      }).firstOrNull;
      if (match != null) return match.id;
    } else if (key.startsWith('name_')) {
      final parts = key.split('_');
      if (parts.length >= 2) {
        final name = parts[1].toLowerCase().trim();
        final match = _registeredPatientsCache.where((s) => s.name.toLowerCase().trim() == name).firstOrNull;
        if (match != null) return match.id;
      }
    }

    return '';
  }

  static Future<_PatientDemographics> _loadDemographics(
    List<DoctorNectAppointmentRecord> records,
    DoctorNectAppointmentRecord latest,
  ) async {
    var bloodGroup = '—';
    var email = '—';
    var familyHistory = 'Not shared with clinic yet.';
    var emergencyContact = EmergencyContact(
      name: '—',
      phone: latest.contactNumber?.trim().isNotEmpty == true ? latest.contactNumber!.trim() : '—',
    );
    const insurance = InsuranceInfo(provider: '—', policyNumber: '—');
    var knownConditions = <String>[];
    var allergies = <AllergyRecord>[];
    DateTime? dateOfBirth;

    String? patientDocId;
    for (final r in records) {
      if (_isFirestorePatientId(r.patientId)) {
        patientDocId = r.patientId;
        break;
      }
    }

    if (patientDocId != null) {
      final doctorId = DoctorSession.loggedInDoctorId;
      if (doctorId.isNotEmpty) {
        await FirestoreService.instance.patientProfile.grantDoctorCareTeamAccess(
          patientId: patientDocId,
          doctorId: doctorId,
        );
      }
      final data =
          await FirestoreService.instance.patientProfile.fetchPatientDocumentForDoctor(patientDocId);
      if (data != null) {
        final bg = (data['bloodGroup'] as String?)?.trim();
        if (bg != null && bg.isNotEmpty) bloodGroup = bg;

        final em = (data['email'] as String?)?.trim();
        if (em != null && em.isNotEmpty) email = em;

        final mobile = (data['mobile'] as String?)?.trim();
        if (mobile != null && mobile.isNotEmpty && emergencyContact.phone == '—') {
          emergencyContact = EmergencyContact(name: latest.patientName, phone: mobile);
        }

        knownConditions = (data['conditions'] as List<dynamic>? ?? const [])
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();

        allergies = (data['allergies'] as List<dynamic>? ?? const [])
            .map((e) => AllergyRecord(name: e.toString().trim(), severity: '—'))
            .where((a) => a.name.isNotEmpty)
            .toList();

        final age = (data['age'] as num?)?.toInt();
        if (age != null && age > 0) {
          dateOfBirth = DateTime(DateTime.now().year - age, 1, 1);
        }
      }
    }

    return _PatientDemographics(
      bloodGroup: bloodGroup,
      email: email,
      emergencyContact: emergencyContact,
      insurance: insurance,
      knownConditions: knownConditions,
      allergies: allergies,
      surgeries: const [],
      familyHistory: familyHistory,
      dateOfBirth: dateOfBirth,
    );
  }

  /// Loads prescriptions from Firestore (or cache) and returns deduped medication list.
  static Future<List<MedicationRecord>> loadMedicationsForProfile(String patientKey) async {
    if (!await canViewClinicalHistoryForKey(patientKey)) {
      return const [];
    }

    await ClinicalPrescriptionStore.instance.refreshForPatient(patientKey, preferCache: true);
    final prescriptions = ClinicalPrescriptionStore.instance.forPatient(patientKey);
    return _currentMedicationsFromPrescriptions(prescriptions);
  }
}

class _PatientDemographics {
  const _PatientDemographics({
    required this.bloodGroup,
    required this.email,
    required this.emergencyContact,
    required this.insurance,
    required this.knownConditions,
    required this.allergies,
    required this.surgeries,
    required this.familyHistory,
    this.dateOfBirth,
  });

  final String bloodGroup;
  final String email;
  final EmergencyContact emergencyContact;
  final InsuranceInfo insurance;
  final List<String> knownConditions;
  final List<AllergyRecord> allergies;
  final List<SurgeryRecord> surgeries;
  final String familyHistory;
  final DateTime? dateOfBirth;
}
