"""Strip Firestore from ambulance_repository.dart — Supabase + callables only."""
from pathlib import Path

p = Path(__file__).resolve().parent.parent / "lib/core/firebase/repositories/ambulance_repository.dart"
text = p.read_text(encoding="utf-8")

# imports
text = text.replace("import 'package:cloud_firestore/cloud_firestore.dart';\n", "")
text = text.replace("import '../../config/firestore_forbidden_guard.dart';\n", "")
text = text.replace("import '../firestore_paths.dart';\n", "")
text = text.replace("import '../firestore_read_helper.dart';\n", "")

# linkDriverAuth body
old = """    try {
      await FirebaseFirestore.instance
          .collection(FirestorePaths.ambulances)
          .doc(ambulanceId)
          .set({'authUid': uid}, SetOptions(merge: true));
      return true;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied' &&
          username != null &&
          pin != null &&
          username.trim().isNotEmpty &&
          pin.trim().length >= 6) {
        return resyncDriverAuth(
          username: username,
          pin: pin,
          expectedDriverId: ambulanceId,
        );
      }
      if (kDebugMode) debugPrint('linkDriverAuth failed: $e');
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('linkDriverAuth failed: $e');
      return false;
    }"""
new = """    if (SupabaseBootstrap.isReady) {
      try {
        await SupabaseBootstrap.client.from('ambulances').update({
          'auth_uid': uid,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('ambulance_id', ambulanceId);
        return true;
      } catch (e) {
        if (kDebugMode) debugPrint('linkDriverAuth Supabase failed: $e');
      }
    }
  if (username != null &&
          pin != null &&
          username.trim().isNotEmpty &&
          pin.trim().length >= 6) {
        return resyncDriverAuth(
          username: username,
          pin: pin,
          expectedDriverId: ambulanceId,
        );
      }
      return false;"""
text = text.replace(old, new)

# saveDriverFcmToken - remove firestore tail (lines 169-188)
text = text.replace(
    """    if (!FirebaseBootstrap.isReady ||
        ambulanceId.isEmpty ||
        token.isEmpty ||
        FirestoreForbiddenGuard.isForbidden) {
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection(FirestorePaths.ambulances)
          .doc(ambulanceId)
          .collection('private')
          .doc('settings')
          .set({
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) debugPrint('saveDriverFcmToken failed: $e');
    }
""",
    "",
)

# clearDriverFcmToken firestore tail — find similar block
import re
text = re.sub(
    r"    if \(!FirebaseBootstrap\.isReady \|\|\s+ambulanceId\.isEmpty\) \{\s+return;\s+\}\s+try \{\s+await FirebaseFirestore\.instance[\s\S]*?clearDriverFcmToken failed.*?\n    \}\n",
    "",
    text,
    count=1,
)

p.write_text(text, encoding="utf-8")
print("partial strip done — manual follow-up may be needed")