abstract final class FirestoreQueryLimits {
  static const prescriptionsPage = 20;
  static const labOrdersPage = 30;
  static const medicalDirectoryPage = 50;
  static const connectionsPage = 30;
  static const pendingConnections = 20;
  static const doctorAppointments = 200;
  static const inAppNotifications = 100;

  /// Verified labs/stores listing cap (`LabRepository`, `MedicalStoreRepository`).
  /// Kept aligned with Firestore list rules (anti-scrape page size).
  static const verifiedDirectoryListingCap = 100;

  // ─── Scale revisit thresholds (audit H8, Jul 2026) ─────────────────────────
  // Revisit pagination / query design when production counts approach these:
  //
  // • Ambulance booking (`FirestoreService.instance.ambulance.fetchAllOnlineDrivers`):
  //   replace full-collection fetch with indexed `isAvailable` + city filter
  //   at ~50+ registered drivers. Also pass preferCache: false on booking path
  //   if drivers report stale availability.
  //
  // • Doctor directory (`DoctorDirectoryRepository`, limit = connectionsPage * 2):
  //   add paginated load-more in patient search at ~50+ verified doctors.
  //
  // • Labs / stores (`fetchVerifiedLabs` / `fetchVerifiedStores`):
  //   paginate registry refresh at ~400+ verified entries (cap is
  //   [verifiedDirectoryListingCap]).
}
