import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../enums/user_type.dart';
import '../supabase/supabase_bootstrap.dart';

/// Persists partial profile drafts across modal closes, page refreshes, and app restarts.
class ProfileDraftStore {
  ProfileDraftStore._();

  static final ProfileDraftStore instance = ProfileDraftStore._();

  static String _key(UserType role, String id) =>
      'profile_draft_${role.name}_${id.trim().toLowerCase()}';

  Future<void> saveDraft({
    required UserType role,
    required String userIdOrPhone,
    required Map<String, dynamic> data,
  }) async {
    final cleanId = userIdOrPhone.trim();
    if (cleanId.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(role, cleanId), jsonEncode(data));

      if (SupabaseBootstrap.isReady) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && uid.isNotEmpty) {
          await SupabaseBootstrap.client.from('users').update({
            'profile_draft': data,
            'profile_draft_updated_at':
                DateTime.now().toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }).or('id.eq.$uid,firebase_uid.eq.$uid');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ProfileDraftStore.saveDraft failed: $e');
      }
    }
  }

  Future<Map<String, dynamic>?> getDraft({
    required UserType role,
    required String userIdOrPhone,
  }) async {
    final cleanId = userIdOrPhone.trim();
    if (cleanId.isEmpty) return null;

    try {
      final prefs = await SharedPreferences.getInstance();
      final localJson = prefs.getString(_key(role, cleanId));
      if (localJson != null && localJson.isNotEmpty) {
        final decoded = jsonDecode(localJson);
        if (decoded is Map<String, dynamic> && decoded.isNotEmpty) {
          return decoded;
        }
      }

      if (SupabaseBootstrap.isReady) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && uid.isNotEmpty) {
          final row = await SupabaseBootstrap.client
              .from('users')
              .select('profile_draft')
              .or('id.eq.$uid,firebase_uid.eq.$uid')
              .maybeSingle();
          final draft = row?['profile_draft'];
          if (draft is Map) {
            return Map<String, dynamic>.from(draft);
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

  Future<void> clearDraft({
    required UserType role,
    required String userIdOrPhone,
  }) async {
    final cleanId = userIdOrPhone.trim();
    if (cleanId.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(role, cleanId));

      if (SupabaseBootstrap.isReady) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && uid.isNotEmpty) {
          await SupabaseBootstrap.client.from('users').update({
            'profile_draft': null,
            'profile_draft_updated_at': null,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }).or('id.eq.$uid,firebase_uid.eq.$uid');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ProfileDraftStore.clearDraft failed: $e');
      }
    }
  }
}
