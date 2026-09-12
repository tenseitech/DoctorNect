import 'app_session.dart';

/// Active diagnostic-lab session for the logged-in lab user.
abstract final class LabSession {
  static String get loggedInLabId => AppSession.labId;
  static set loggedInLabId(String v) => AppSession.labId = v;

  static String get loggedInLabName => AppSession.labName;
  static set loggedInLabName(String v) => AppSession.labName = v;

  static void setLab({required String id, required String name}) =>
      AppSession.setLab(id: id, name: name);

  static void clear() {
    AppSession.labId = '';
    AppSession.labName = '';
  }
}
