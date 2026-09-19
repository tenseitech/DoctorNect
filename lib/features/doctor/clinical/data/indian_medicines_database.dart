import 'dart:convert' show utf8;

import 'package:archive/archive.dart' show GZipDecoder;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'clinical_mock_data.dart';

/// Loads ~250k Indian medicine names from the bundled asset on first use.
/// Builds a first-2-char prefix index so live search stays sub-millisecond
/// even with hundreds of thousands of entries.
class IndianMedicinesDatabase {
  IndianMedicinesDatabase._();

  static final IndianMedicinesDatabase instance = IndianMedicinesDatabase._();

  static const _assetPath = 'assets/data/indian_medicines.txt.gz';

  List<String>? _names;

  /// `aa` -> list of names that start with `aa` (lowercase).
  final Map<String, List<String>> _twoCharIndex = {};

  /// `a` -> list of names that start with `a` (lowercase) but are too short
  /// to fit in `_twoCharIndex`. Combined with all `a*` two-char buckets for
  /// single-letter queries.
  final Map<String, List<String>> _singleCharIndex = {};

  Future<void>? _loading;

  bool get isLoaded => _names != null;

  Future<void> ensureLoaded() {
    if (_names != null) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final byteData = await rootBundle.load(_assetPath);
      final compressed = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      final decompressed = GZipDecoder().decodeBytes(compressed);
      final raw = utf8.decode(decompressed, allowMalformed: true);
      final lines = <String>[];
      var start = 0;
      for (var i = 0; i < raw.length; i++) {
        final ch = raw.codeUnitAt(i);
        if (ch == 0x0A) {
          if (i > start) {
            final line = raw.substring(start, i).trimRight();
            if (line.isNotEmpty) lines.add(line);
          }
          start = i + 1;
        }
      }
      if (start < raw.length) {
        final line = raw.substring(start).trimRight();
        if (line.isNotEmpty) lines.add(line);
      }

      _buildIndex(lines);
      _names = lines;
    } catch (error, stackTrace) {
      debugPrint(
          'IndianMedicinesDatabase: asset load failed, using fallback list. $error');
      debugPrint('$stackTrace');
      final fallback = List<String>.from(ClinicalMockData.drugSuggestions);
      _buildIndex(fallback);
      _names = fallback;
    }
  }

  void _buildIndex(List<String> lines) {
    _twoCharIndex.clear();
    _singleCharIndex.clear();
    for (final n in lines) {
      if (n.isEmpty) continue;
      final c1 = n.codeUnitAt(0).toLowerCase();
      final s1 = String.fromCharCode(c1);
      _singleCharIndex.putIfAbsent(s1, () => <String>[]).add(n);
      if (n.length >= 2) {
        final key = '$s1${String.fromCharCode(n.codeUnitAt(1).toLowerCase())}';
        _twoCharIndex.putIfAbsent(key, () => <String>[]).add(n);
      }
    }
  }

  /// Returns up to [limit] suggestions matching [query].
  /// - Prefix matches first (via first-letter / two-letter index).
  /// - Falls back to substring scan only for short single-letter inputs.
  List<String> search(String query, {int limit = 8}) {
    final names = _names;
    if (names == null) return const [];
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return names.take(limit).toList();

    if (q.length == 1) {
      final bucket = _singleCharIndex[q];
      if (bucket == null) return const [];
      return bucket.length > limit ? bucket.sublist(0, limit) : List.of(bucket);
    }

    final twoKey = q.substring(0, 2);
    final bucket = _twoCharIndex[twoKey];
    if (bucket == null) return const [];

    if (q.length == 2) {
      return bucket.length > limit ? bucket.sublist(0, limit) : List.of(bucket);
    }

    final results = <String>[];
    for (final n in bucket) {
      if (n.length >= q.length && n.substring(0, q.length).toLowerCase() == q) {
        results.add(n);
        if (results.length >= limit) break;
      }
    }
    return results;
  }
}

extension on int {
  int toLowerCase() {
    if (this >= 0x41 && this <= 0x5A) return this + 32;
    return this;
  }
}
