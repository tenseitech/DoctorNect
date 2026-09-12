import 'package:cloud_firestore/cloud_firestore.dart';

import 'firebase_bootstrap.dart';

abstract final class FirestoreReadHelper {
  static Future<QuerySnapshot<T>> getQuery<T>({
    required Query<T> query,
    bool preferCache = true,
    bool onlyCache = false,
    /// When true, skips the "return cache immediately if non-empty" shortcut so
    /// the server is always queried. Scoped to appointment reads — other callers
    /// keep the default cache-first behaviour.
    bool requireServerIfCacheNonEmpty = false,
  }) async {
    if (preferCache &&
        !requireServerIfCacheNonEmpty &&
        FirebaseBootstrap.isReady) {
      try {
        final cached = await query.get(const GetOptions(source: Source.cache));
        if (cached.docs.isNotEmpty) {
          return cached;
        }
      } catch (_) {}
    }

    if (onlyCache) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'cache-empty',
        message: 'Cache is empty',
      );
    }

    return query.get(const GetOptions(source: Source.server));
  }

  static Future<DocumentSnapshot<T>> getDocument<T>({
    required DocumentReference<T> reference,
    bool preferCache = true,
  }) async {
    if (preferCache && FirebaseBootstrap.isReady) {
      try {
        final cached = await reference.get(const GetOptions(source: Source.cache));
        if (cached.exists) {
          return cached;
        }
      } catch (_) {}
    }

    return reference.get(const GetOptions(source: Source.server));
  }
}
