import 'dart:async';
import 'dart:io';

import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// App-level AES-256-GCM encryption for PHI files cached on device or in web memory.
abstract final class FileEncryptionService {
  FileEncryptionService._();

  static const _storageKey = 'phi_file_encryption_key_v1';
  static const _magic = 'DNPHI1';
  static const _formatVersion = 1;
  static const _nonceLength = 12;
  static const _isolateThresholdBytes = 512 * 1024;

  static const _secureStorage = FlutterSecureStorage(
    iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  static encrypt.Key? _cachedKey;
  static Future<void>? _initFuture;

  static Future<void> ensureInitialized() {
    return _initFuture ??= _loadOrCreateKey();
  }

  static Future<void> _loadOrCreateKey() async {
    final stored = await _secureStorage.read(key: _storageKey);
    if (stored != null && stored.isNotEmpty) {
      _cachedKey = encrypt.Key.fromBase64(stored);
      return;
    }

    final key = encrypt.Key.fromSecureRandom(32);
    await _secureStorage.write(key: _storageKey, value: key.base64);
    _cachedKey = key;
  }

  static encrypt.Key _requireKey() {
    final key = _cachedKey;
    if (key == null) {
      throw StateError(
          'FileEncryptionService.ensureInitialized() was not called.');
    }
    return key;
  }

  static String encryptedFileName(String sanitizedBaseName) =>
      '$sanitizedBaseName.enc';

  static bool looksEncrypted(Uint8List bytes) {
    if (bytes.length < _magic.length + 1 + _nonceLength + 16) return false;
    return String.fromCharCodes(bytes.sublist(0, _magic.length)) == _magic;
  }

  static Future<Uint8List> encryptBytes(Uint8List plain) async {
    await ensureInitialized();
    final keyBytes = Uint8List.fromList(_requireKey().bytes);
    if (plain.length >= _isolateThresholdBytes) {
      return compute(_encryptPayload, _CipherPayload(keyBytes, plain));
    }
    return _encryptPayload(_CipherPayload(keyBytes, plain));
  }

  static Future<Uint8List> decryptBytes(Uint8List encryptedBytes) async {
    await ensureInitialized();
    final keyBytes = Uint8List.fromList(_requireKey().bytes);
    if (encryptedBytes.length >= _isolateThresholdBytes) {
      return compute(_decryptPayload, _CipherPayload(keyBytes, encryptedBytes));
    }
    return _decryptPayload(_CipherPayload(keyBytes, encryptedBytes));
  }

  /// Web / legacy memory entries may still hold plain bytes from older sessions.
  static Future<Uint8List?> decryptFromMemoryCache(Uint8List? cached) async {
    if (cached == null || cached.isEmpty) return null;
    if (!looksEncrypted(cached)) return cached;
    try {
      return await decryptBytes(cached);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint(
            'FileEncryptionService.decryptFromMemoryCache failed: $e\n$st');
      }
      return null;
    }
  }

  static Future<Uint8List> encryptForMemoryCache(Uint8List plain) =>
      encryptBytes(plain);

  static Future<bool> writeDiskFile({
    required String directoryPath,
    required String sanitizedFileName,
    required Uint8List plain,
  }) async {
    if (plain.isEmpty) return false;

    final dir = Directory(directoryPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final encrypted = await encryptBytes(plain);
    final encFile =
        File('$directoryPath/${encryptedFileName(sanitizedFileName)}');
    await encFile.writeAsBytes(encrypted, flush: true);

    final legacy = File('$directoryPath/$sanitizedFileName');
    if (legacy.existsSync()) {
      try {
        await legacy.delete();
      } catch (_) {}
    }
    return true;
  }

  /// Reads `.enc` first; falls back to legacy plain file and migrates lazily.
  static Future<Uint8List?> readDiskFileWithLegacyMigration({
    required String directoryPath,
    required String sanitizedFileName,
  }) async {
    final encFile =
        File('$directoryPath/${encryptedFileName(sanitizedFileName)}');
    if (encFile.existsSync()) {
      final raw = await encFile.readAsBytes();
      if (looksEncrypted(raw)) {
        try {
          return await decryptBytes(raw);
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint(
                'FileEncryptionService.readDiskFile decrypt failed: $e\n$st');
          }
          return null;
        }
      }
    }

    final legacyFile = File('$directoryPath/$sanitizedFileName');
    if (!legacyFile.existsSync()) return null;

    final plain = await legacyFile.readAsBytes();
    unawaited(
      writeDiskFile(
        directoryPath: directoryPath,
        sanitizedFileName: sanitizedFileName,
        plain: plain,
      ),
    );
    return plain;
  }

  static Future<void> deleteDiskFiles({
    required String directoryPath,
    required String sanitizedFileName,
  }) async {
    final encFile =
        File('$directoryPath/${encryptedFileName(sanitizedFileName)}');
    if (encFile.existsSync()) {
      try {
        await encFile.delete();
      } catch (_) {}
    }

    final legacyFile = File('$directoryPath/$sanitizedFileName');
    if (legacyFile.existsSync()) {
      try {
        await legacyFile.delete();
      } catch (_) {}
    }
  }
}

class _CipherPayload {
  const _CipherPayload(this.keyBytes, this.data);

  final Uint8List keyBytes;
  final Uint8List data;
}

Uint8List _encryptPayload(_CipherPayload payload) {
  final key = encrypt.Key(payload.keyBytes);
  final iv = encrypt.IV.fromSecureRandom(FileEncryptionService._nonceLength);
  final encrypter =
      encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));
  final cipher = encrypter.encryptBytes(payload.data, iv: iv);

  final out = Uint8List(
    FileEncryptionService._magic.length +
        1 +
        iv.bytes.length +
        cipher.bytes.length,
  );
  var offset = 0;
  out.setRange(offset, offset + FileEncryptionService._magic.length,
      FileEncryptionService._magic.codeUnits);
  offset += FileEncryptionService._magic.length;
  out[offset] = FileEncryptionService._formatVersion;
  offset += 1;
  out.setRange(offset, offset + iv.bytes.length, iv.bytes);
  offset += iv.bytes.length;
  out.setRange(offset, out.length, cipher.bytes);
  return out;
}

Uint8List _decryptPayload(_CipherPayload payload) {
  final bytes = payload.data;
  if (!FileEncryptionService.looksEncrypted(bytes)) {
    throw FormatException('Not an encrypted PHI file blob');
  }

  var offset = FileEncryptionService._magic.length + 1;
  final iv = encrypt
      .IV(bytes.sublist(offset, offset + FileEncryptionService._nonceLength));
  offset += FileEncryptionService._nonceLength;
  final cipherBytes = bytes.sublist(offset);

  final key = encrypt.Key(payload.keyBytes);
  final encrypter =
      encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.gcm));
  final decrypted =
      encrypter.decryptBytes(encrypt.Encrypted(cipherBytes), iv: iv);
  return Uint8List.fromList(decrypted);
}
