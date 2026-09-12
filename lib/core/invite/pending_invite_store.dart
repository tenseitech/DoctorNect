/// Centralized store capturing invite query parameters from deep links.
abstract final class PendingInviteStore {
  static String? doctorId;
  static String? labId;
  static String? pharmacyId;
  static String? ambulanceInviteId;
  static String? ambulanceToken;
  static String? role;
  static String? email;
  static bool isSuperAdminPortal = false;

  static bool get hasPendingAmbulance =>
      ambulanceInviteId != null &&
      ambulanceInviteId!.isNotEmpty &&
      ambulanceToken != null &&
      ambulanceToken!.isNotEmpty;

  static void captureFromUri(Uri uri) {
    final rawEmail = uri.queryParameters['email']?.trim();
    if (rawEmail != null && rawEmail.isNotEmpty) {
      email = rawEmail;
    }

    final rawRole = uri.queryParameters['role']?.trim().toLowerCase();
    if (rawRole != null && rawRole.isNotEmpty) {
      role = rawRole;
    }

    final portalParam = uri.queryParameters['portal']?.trim().toLowerCase();
    final adminParam = uri.queryParameters['admin']?.trim().toLowerCase();
    final hasAdminPath = uri.pathSegments.any((s) =>
        s == '_admin_portal' ||
        s == 'ops-portal' ||
        s == 'super-admin-portal' ||
        s == '_admin');
    final hasAdminFragment = uri.fragment.contains('_admin_portal') ||
        uri.fragment.contains('ops-portal') ||
        uri.fragment.contains('super-admin-portal') ||
        uri.fragment.contains('_admin');

    if (portalParam == 'super_admin' ||
        adminParam == 'super_admin' ||
        adminParam == 'true' ||
        hasAdminPath ||
        hasAdminFragment ||
        rawRole == 'super_admin') {
      isSuperAdminPortal = true;
    }

    final doctor = uri.queryParameters['doctor']?.trim();
    if (doctor != null && doctor.isNotEmpty) {
      doctorId = doctor;
    } else {
      final segments = uri.pathSegments;
      if (segments.length >= 2 && segments.first == 'join') {
        final id = segments[1].trim();
        if (id.isNotEmpty) doctorId = id;
      }
    }

    final lab = uri.queryParameters['lab']?.trim();
    if (lab != null && lab.isNotEmpty) {
      labId = lab;
    }

    final store = uri.queryParameters['store']?.trim();
    if (store != null && store.isNotEmpty) {
      if (rawRole == null || rawRole == 'doctor') {
        pharmacyId = store;
      }
    }

    final invite = uri.queryParameters['invite']?.trim();
    final token = uri.queryParameters['token']?.trim();
    if (invite != null && invite.isNotEmpty && token != null && token.isNotEmpty) {
      ambulanceInviteId = invite;
      ambulanceToken = token;
    } else {
      final segments = uri.pathSegments;
      if (segments.isNotEmpty &&
          (segments.first == 'ambulance-setup' || segments.last == 'ambulance-setup')) {
        final fromPathInvite = uri.queryParameters['invite']?.trim();
        final fromPathToken = uri.queryParameters['token']?.trim();
        if (fromPathInvite != null &&
            fromPathInvite.isNotEmpty &&
            fromPathToken != null &&
            fromPathToken.isNotEmpty) {
          ambulanceInviteId = fromPathInvite;
          ambulanceToken = fromPathToken;
        }
      }
    }
  }

  static void clear() {
    doctorId = null;
    labId = null;
    pharmacyId = null;
    ambulanceInviteId = null;
    ambulanceToken = null;
    role = null;
    email = null;
    isSuperAdminPortal = false;
  }
}
