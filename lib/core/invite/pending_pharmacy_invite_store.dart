import 'pending_invite_store.dart';

/// Captures `?store=&role=doctor` invite deep links before doctor registration.
abstract final class PendingPharmacyInviteStore {
  static String? get pendingStoreId => PendingInviteStore.pharmacyId;

  static void captureFromUri(Uri uri) => PendingInviteStore.captureFromUri(uri);
  static void clear() => PendingInviteStore.clear();
}
