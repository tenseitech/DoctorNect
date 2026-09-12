import 'pending_invite_store.dart';

/// Captures `?lab=` invite deep links before lab or doctor registration.
abstract final class PendingLabInviteStore {
  static String? get pendingLabId => PendingInviteStore.labId;
  static String? get pendingRole => PendingInviteStore.role;

  static void captureFromUri(Uri uri) => PendingInviteStore.captureFromUri(uri);
  static void clear() => PendingInviteStore.clear();
}
