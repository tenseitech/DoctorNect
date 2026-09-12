import 'app_session.dart';

/// Active doctor session for the logged-in user.
abstract final class DoctorSession {
  static String get loggedInDoctorId => AppSession.doctorId;
  static set loggedInDoctorId(String v) => AppSession.doctorId = v;

  static String get loggedInDoctorName => AppSession.doctorName;
  static set loggedInDoctorName(String v) => AppSession.doctorName = v;

  static String get activeDoctorId => AppSession.activeDoctorId;

  static void setDoctor({required String id, required String name}) =>
      AppSession.setDoctor(id: id, name: name);

  static void clear() {
    AppSession.doctorId = '';
    AppSession.doctorName = '';
  }
}
