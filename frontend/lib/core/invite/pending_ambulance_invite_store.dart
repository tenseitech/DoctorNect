import 'pending_invite_store.dart';

/// Captures ambulance driver invite deep links before PIN setup.
abstract final class PendingAmbulanceInviteStore {
  static String? get inviteId => PendingInviteStore.ambulanceInviteId;
  static String? get token => PendingInviteStore.ambulanceToken;

  static bool get hasPending => PendingInviteStore.hasPendingAmbulance;

  static void captureFromUri(Uri uri) => PendingInviteStore.captureFromUri(uri);
  static void clear() => PendingInviteStore.clear();
}
