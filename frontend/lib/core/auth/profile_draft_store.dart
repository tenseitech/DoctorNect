import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../enums/user_type.dart';
import '../firebase/firebase_bootstrap.dart';
import '../firebase/firestore_paths.dart';

/// Persists partial profile drafts across modal closes, page refreshes, and app restarts.
///
/// Saves to both [SharedPreferences] (local instant availability) and
/// Cloud Firestore `users/{uid}.profileDraft` (database durability).
class ProfileDraftStore {
  ProfileDraftStore._();

  static final ProfileDraftStore instance = ProfileDraftStore._();

  static String _key(UserType role, String id) =>
      'profile_draft_${role.name}_${id.trim().toLowerCase()}';

  /// Saves a draft map to both local storage and Firestore.
  Future<void> saveDraft({
    required UserType role,
    required String userIdOrPhone,
    required Map<String, dynamic> data,
  }) async {
    final cleanId = userIdOrPhone.trim();
    if (cleanId.isEmpty) return;

    try {
      // 1. Local persistent storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(role, cleanId), jsonEncode(data));

      // 2. Firestore cloud draft persistence
      if (FirebaseBootstrap.isReady) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && uid.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection(FirestorePaths.users)
              .doc(uid)
              .set({
            'profileDraft': data,
            'profileDraftUpdatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ProfileDraftStore.saveDraft failed: $e');
      }
    }
  }

  /// Retrieves any saved draft for the given user/role.
  Future<Map<String, dynamic>?> getDraft({
    required UserType role,
    required String userIdOrPhone,
  }) async {
    final cleanId = userIdOrPhone.trim();
    if (cleanId.isEmpty) return null;

    try {
      // 1. Try local storage first
      final prefs = await SharedPreferences.getInstance();
      final localJson = prefs.getString(_key(role, cleanId));
      if (localJson != null && localJson.isNotEmpty) {
        final decoded = jsonDecode(localJson);
        if (decoded is Map<String, dynamic> && decoded.isNotEmpty) {
          return decoded;
        }
      }

      // 2. Try Firestore cloud backup
      if (FirebaseBootstrap.isReady) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && uid.isNotEmpty) {
          final doc = await FirebaseFirestore.instance
              .collection(FirestorePaths.users)
              .doc(uid)
              .get();
          final data = doc.data();
          if (data != null && data['profileDraft'] is Map) {
            return Map<String, dynamic>.from(data['profileDraft'] as Map);
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ProfileDraftStore.getDraft failed: $e');
      }
    }
    return null;
  }

  /// Clears the draft after a successful profile save.
  Future<void> clearDraft({
    required UserType role,
    required String userIdOrPhone,
  }) async {
    final cleanId = userIdOrPhone.trim();
    if (cleanId.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(role, cleanId));

      if (FirebaseBootstrap.isReady) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && uid.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection(FirestorePaths.users)
              .doc(uid)
              .update({
            'profileDraft': FieldValue.delete(),
          });
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ProfileDraftStore.clearDraft failed: $e');
      }
    }
  }
}
