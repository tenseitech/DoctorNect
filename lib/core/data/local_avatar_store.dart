import 'dart:convert';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Unified on-device profile photo caching and persistence.
abstract final class LocalAvatarStore {
  static const maxFileBytes = 5 * 1024 * 1024;
  static final Map<String, Uint8List> _memory = {};

  static String _key(String role, String id) => '${role}_photo_$id';

  static Future<File?> _photoFile(String role, String id) async {
    if (kIsWeb) return null;
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/${role}_photos');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return File('${dir.path}/$id.jpg');
  }

  static Uint8List? readCached(String role, String id) {
    if (id.isEmpty) return null;
    return _memory[_key(role, id)];
  }

  static Future<Uint8List?> load(String role, String id) async {
    if (id.isEmpty) return null;
    final key = _key(role, id);
    final cached = _memory[key];
    if (cached != null) return cached;

    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final b64 = prefs.getString(key);
        if (b64 != null && b64.isNotEmpty) {
          final bytes = base64Decode(b64);
          _memory[key] = bytes;
          return bytes;
        }
      } catch (_) {}
      return null;
    }

    try {
      final file = await _photoFile(role, id);
      if (file != null && file.existsSync()) {
        final bytes = await file.readAsBytes();
        _memory[key] = bytes;
        return bytes;
      }
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      final b64 = prefs.getString(key);
      if (b64 != null && b64.isNotEmpty) {
        final bytes = base64Decode(b64);
        await save(role, id, bytes);
        return bytes;
      }
    } catch (_) {}

    return null;
  }

  static Future<bool> save(String role, String id, Uint8List bytes) async {
    if (id.isEmpty || bytes.isEmpty || bytes.length > maxFileBytes) return false;
    final key = _key(role, id);
    _memory[key] = bytes;

    if (kIsWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(key, base64Encode(bytes));
      } catch (_) {}
      return true;
    }

    try {
      final file = await _photoFile(role, id);
      if (file != null) {
        await file.writeAsBytes(bytes, flush: true);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, base64Encode(bytes));
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> clear(String role, String id) async {
    final key = _key(role, id);
    _memory.remove(key);

    if (!kIsWeb) {
      try {
        final file = await _photoFile(role, id);
        if (file != null && file.existsSync()) {
          await file.delete();
        }
      } catch (_) {}
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {}
  }

  static Future<String?> uploadToFirebaseStorage({
    required String storagePath,
    required String role,
    required String id,
    Uint8List? bytes,
  }) async {
    if (id.isEmpty) return null;
    final data = bytes ?? readCached(role, id) ?? await load(role, id);
    if (data == null || data.isEmpty) return null;
    try {
      final ref = FirebaseStorage.instance.ref(storagePath);
      await ref.putData(data, SettableMetadata(contentType: 'image/jpeg'));
      return await ref.getDownloadURL();
    } catch (e) {
      if (kDebugMode) debugPrint('[LocalAvatarStore] storage upload failed: $e');
      return null;
    }
  }
}
