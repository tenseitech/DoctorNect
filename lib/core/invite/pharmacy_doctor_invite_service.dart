import 'package:cloud_firestore/cloud_firestore.dart';

import '../firebase/firebase_bootstrap.dart';
import '../firebase/firestore_paths.dart';
import '../session/medical_store_session.dart';
import '../../features/pharmacy/data/medical_store_registry.dart';

/// Pharmacy → doctor invite links for non-registered doctors.
abstract final class PharmacyDoctorInviteService {
  static const appDownloadUrl = 'https://doctornect.com/download';

  static String buildInviteLink(String storeId) {
    final id = storeId.trim().isEmpty ? 'store' : storeId.trim();
    return Uri.parse(appDownloadUrl).replace(queryParameters: {
      'store': id,
      'role': 'doctor',
    }).toString();
  }

  static String inviteMessage(
      {required String storeName, required String link}) {
    final name =
        storeName.trim().isEmpty ? 'A medical store' : storeName.trim();
    return '$name invited you to download DoctorNect and register as a doctor to connect with their pharmacy. '
        'Download the app and sign up using this link:\n$link';
  }

  static Future<void> ensureInviteMetadata(String storeId) async {
    if (!FirebaseBootstrap.isReady || storeId.isEmpty) return;

    await FirebaseFirestore.instance
        .collection(FirestorePaths.medicalStores)
        .doc(storeId)
        .set({
      'doctorInviteLink': buildInviteLink(storeId),
      'doctorInviteUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<String> linkForCurrentStore() async {
    final storeId = MedicalStoreSession.loggedInStoreId;
    if (storeId.isEmpty) return buildInviteLink('store');

    await MedicalStoreRegistry.ensureStoreLoaded(storeId);
    await ensureInviteMetadata(storeId);
    return buildInviteLink(storeId);
  }

  static String storeNameForCurrentStore() {
    final storeId = MedicalStoreSession.loggedInStoreId;
    final store = MedicalStoreRegistry.findById(storeId);
    final name = store?.storeName.trim();
    if (name != null && name.isNotEmpty) return name;
    final sessionName = MedicalStoreSession.loggedInStoreName.trim();
    return sessionName.isEmpty ? 'Your pharmacy' : sessionName;
  }
}
