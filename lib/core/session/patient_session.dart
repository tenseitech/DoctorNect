import 'app_session.dart';

/// Active patient session for the logged-in user.
abstract final class PatientSession {
  static String get loggedInPatientId => AppSession.patientId;
  static set loggedInPatientId(String v) => AppSession.patientId = v;

  static String get loggedInPatientName => AppSession.patientName;
  static set loggedInPatientName(String v) => AppSession.patientName = v;

  static String get patientKey => AppSession.patientKey;
  static set patientKey(String v) => AppSession.patientKey = v;

  static void setPatient({required String id, required String name}) =>
      AppSession.setPatient(id: id, name: name);

  static void clear() {
    AppSession.patientId = '';
    AppSession.patientName = '';
    AppSession.patientKey = '';
  }
}
