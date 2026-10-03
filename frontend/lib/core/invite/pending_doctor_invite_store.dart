import 'pending_invite_store.dart';

/// Captures `?doctor=` and `?role=` invite deep links before registration.
abstract final class PendingDoctorInviteStore {
  static String? get pendingDoctorId => PendingInviteStore.doctorId;
  static String? get pendingRole => PendingInviteStore.role;

  static void captureFromUri(Uri uri) => PendingInviteStore.captureFromUri(uri);
  static void clear() => PendingInviteStore.clear();
}
