import 'app_session.dart';

/// Active medical store session for the logged-in pharmacy user.
abstract final class MedicalStoreSession {
  static String get loggedInStoreId => AppSession.storeId;
  static set loggedInStoreId(String v) => AppSession.storeId = v;

  static String get loggedInStoreName => AppSession.storeName;
  static set loggedInStoreName(String v) => AppSession.storeName = v;

  static void setStore({required String id, required String name}) =>
      AppSession.setStore(id: id, name: name);

  static void clear() {
    AppSession.storeId = '';
    AppSession.storeName = '';
  }
}
