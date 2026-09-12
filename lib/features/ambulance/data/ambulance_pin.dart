import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Salted PBKDF2-HMAC-SHA256 PIN hashes (compatible with Cloud Functions).
///
/// Stored format: `pbkdf2$sha256$<iterations>$<saltHex>$<hashHex>`
/// Also verifies legacy `pbkdf2$<iterations>$<salt>$<hash>` and unsalted SHA-256.
abstract final class AmbulancePin {
  static const int _iterations = 120000;
  static const int _keyLength = 32;
  static final _legacySha256 = RegExp(r'^[a-f0-9]{64}$', caseSensitive: false);

  /// Creates a new salted PBKDF2 hash of [pin].
  static String hash(String pin) {
    final salt = _randomSalt(16);
    final derived = _pbkdf2(
      password: utf8.encode(pin.trim()),
      salt: salt,
      iterations: _iterations,
      dkLen: _keyLength,
    );
    return 'pbkdf2\$sha256\$$_iterations\$${_toHex(salt)}\$${_toHex(derived)}';
  }

  /// True when [storedPin] is a recognized hash format.
  static bool isStoredHash(String storedPin) {
    final stored = storedPin.trim();
    if (stored.startsWith('pbkdf2\$')) return true;
    return stored.length == 64 && _legacySha256.hasMatch(stored);
  }

  /// Compares [enteredPin] against a stored hash.
  static bool matches({required String storedPin, required String enteredPin}) {
    final stored = storedPin.trim();
    final entered = enteredPin.trim();
    if (entered.isEmpty) return false;

    if (stored.startsWith('pbkdf2\$sha256\$')) {
      final parts = stored.split('\$');
      if (parts.length != 5) return false;
      final iterations = int.tryParse(parts[2]) ?? 0;
      final salt = _fromHex(parts[3]);
      final expected = _fromHex(parts[4]);
      if (iterations < 10000 || salt.isEmpty || expected.isEmpty) return false;
      final actual = _pbkdf2(
        password: utf8.encode(entered),
        salt: salt,
        iterations: iterations,
        dkLen: expected.length,
      );
      return _constantTimeEquals(actual, expected);
    }

    if (stored.startsWith('pbkdf2\$')) {
      final parts = stored.split('\$');
      if (parts.length == 4) {
        final iterations = int.tryParse(parts[1]) ?? 0;
        final salt = _fromHex(parts[2]);
        final expected = _fromHex(parts[3]);
        if (iterations < 10000 || salt.isEmpty || expected.isEmpty) return false;
        final actual = _pbkdf2(
          password: utf8.encode(entered),
          salt: salt,
          iterations: iterations,
          dkLen: expected.length,
        );
        return _constantTimeEquals(actual, expected);
      }
    }

    if (stored.length == 64 && _legacySha256.hasMatch(stored)) {
      final legacy = sha256.convert(utf8.encode(entered)).toString();
      return _constantTimeEquals(
        utf8.encode(legacy.toLowerCase()),
        utf8.encode(stored.toLowerCase()),
      );
    }
    return false;
  }

  static Uint8List _randomSalt(int length) {
    final random = Random.secure();
    return Uint8List.fromList(List<int>.generate(length, (_) => random.nextInt(256)));
  }

  static String _toHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _fromHex(String hex) {
    final clean = hex.trim();
    final out = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// PBKDF2-HMAC-SHA256 (RFC 8018).
  static Uint8List _pbkdf2({
    required List<int> password,
    required List<int> salt,
    required int iterations,
    required int dkLen,
  }) {
    final hmac = Hmac(sha256, password);
    final hLen = 32;
    final blockCount = (dkLen + hLen - 1) ~/ hLen;
    final result = BytesBuilder(copy: false);

    for (var block = 1; block <= blockCount; block++) {
      final blockSalt = BytesBuilder(copy: false)
        ..add(salt)
        ..add([(block >> 24) & 0xff, (block >> 16) & 0xff, (block >> 8) & 0xff, block & 0xff]);
      var u = Uint8List.fromList(hmac.convert(blockSalt.toBytes()).bytes);
      final t = Uint8List.fromList(u);
      for (var i = 1; i < iterations; i++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      result.add(t);
    }

    return Uint8List.fromList(result.toBytes().sublist(0, dkLen));
  }
}
