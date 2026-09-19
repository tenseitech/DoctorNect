import 'package:cloud_firestore/cloud_firestore.dart';

import '../firebase_bootstrap.dart';
import '../firestore_paths.dart';
import '../firestore_read_helper.dart';

class DoctorDeactivationStatus {
  const DoctorDeactivationStatus({
    required this.deactivated,
    required this.canReactivate,
    this.reactivateBefore,
  });

  final bool deactivated;
  final bool canReactivate;
  final DateTime? reactivateBefore;
}

class DoctorAccountRepository {
  DoctorAccountRepository._();

  static final DoctorAccountRepository instance = DoctorAccountRepository._();

  bool _isTruthy(dynamic value) {
    if (value == true) return true;
    if (value is String) return value.toLowerCase() == 'true';
    return false;
  }

  DateTime? _readTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  Future<DoctorDeactivationStatus> fetchDeactivationStatus(
    String doctorId, {
    bool preferCache = false,
  }) async {
    if (!FirebaseBootstrap.isReady) {
      return const DoctorDeactivationStatus(
          deactivated: false, canReactivate: false);
    }

    try {
      final snap = await FirestoreReadHelper.getDocument(
        reference: FirebaseFirestore.instance
            .collection(FirestorePaths.doctors)
            .doc(doctorId),
        preferCache: preferCache,
      );
      if (!snap.exists || snap.data() == null) {
        return const DoctorDeactivationStatus(
            deactivated: false, canReactivate: false);
      }

      final data = snap.data()!;
      final reactivateBefore = _readTimestamp(data['reactivateBefore']);
      var deactivated = _isTruthy(data['deactivated']);

      // Fallback: some docs only show reactivateBefore (no boolean toggle in console).
      if (!deactivated &&
          reactivateBefore != null &&
          !_isTruthy(data['verified']) &&
          DateTime.now().isBefore(reactivateBefore)) {
        deactivated = true;
      }

      if (!deactivated) {
        return const DoctorDeactivationStatus(
            deactivated: false, canReactivate: false);
      }

      final canReactivate =
          reactivateBefore != null && DateTime.now().isBefore(reactivateBefore);

      return DoctorDeactivationStatus(
        deactivated: true,
        canReactivate: canReactivate,
        reactivateBefore: reactivateBefore,
      );
    } catch (_) {
      return const DoctorDeactivationStatus(
          deactivated: false, canReactivate: false);
    }
  }

  Future<bool> isDeactivated(String doctorId,
      {bool preferCache = false}) async {
    final status =
        await fetchDeactivationStatus(doctorId, preferCache: preferCache);
    return status.deactivated;
  }

  Future<bool> isVerified(String doctorId, {bool preferCache = false}) async {
    if (!FirebaseBootstrap.isReady) return false;
    try {
      final snap = await FirestoreReadHelper.getDocument(
        reference: FirebaseFirestore.instance
            .collection(FirestorePaths.doctors)
            .doc(doctorId),
        preferCache: preferCache,
      );
      if (!snap.exists || snap.data() == null) return false;
      return _isTruthy(snap.data()!['verified']);
    } catch (_) {
      return false;
    }
  }

  Future<void> deactivate({
    required String doctorId,
    required String ownerUid,
  }) async {
    if (!FirebaseBootstrap.isReady) {
      throw StateError('Firebase is not available.');
    }

    final reactivateBefore = DateTime.now().add(const Duration(days: 30));
    final batch = FirebaseFirestore.instance.batch();
    final doctorRef = FirebaseFirestore.instance
        .collection(FirestorePaths.doctors)
        .doc(doctorId);
    final userRef = FirebaseFirestore.instance
        .collection(FirestorePaths.users)
        .doc(ownerUid);

    batch.update(doctorRef, {
      'deactivated': true,
      'verified': false,
      'deactivatedAt': FieldValue.serverTimestamp(),
      'reactivateBefore': Timestamp.fromDate(reactivateBefore),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(userRef, {
      'deactivated': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  Future<void> reactivate({
    required String doctorId,
    required String ownerUid,
  }) async {
    if (!FirebaseBootstrap.isReady) {
      throw StateError('Firebase is not available.');
    }

    final status = await fetchDeactivationStatus(doctorId);
    if (!status.deactivated) return;
    if (!status.canReactivate) {
      throw StateError('Reactivation window has expired.');
    }

    final batch = FirebaseFirestore.instance.batch();
    final doctorRef = FirebaseFirestore.instance
        .collection(FirestorePaths.doctors)
        .doc(doctorId);
    final userRef = FirebaseFirestore.instance
        .collection(FirestorePaths.users)
        .doc(ownerUid);

    batch.update(doctorRef, {
      'deactivated': false,
      'verified':
          false, // FIXED: reactivation must go through admin re-approval, like registration
      'reactivatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.update(userRef, {
      'deactivated': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }
}
