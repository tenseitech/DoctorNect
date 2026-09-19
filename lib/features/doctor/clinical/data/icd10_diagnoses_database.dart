import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'clinical_mock_data.dart';

/// Loads ICD-10 diagnosis lines from [assetPath].
///
/// Supported line formats:
/// - CMS tabular: `00001 A00     0 Cholera ... Cholera`
/// - `J06.9 - Acute upper respiratory infection`
/// - `J06.9<Tab>Acute upper respiratory infection`
/// - `J06.9 Acute upper respiratory infection`
class Icd10DiagnosesDatabase {
  Icd10DiagnosesDatabase._();

  static final Icd10DiagnosesDatabase instance = Icd10DiagnosesDatabase._();

  static const assetPath = 'assets/data/icd10_diagnoses.txt';

  List<_Icd10Entry>? _entries;
  Set<String>? _displayLower;
  final Map<String, List<int>> _codeByFirstChar = {};
  final Map<String, List<int>> _descByFirstChar = {};
  Future<void>? _loading;

  bool get isLoaded => _entries != null;

  Future<void> ensureLoaded() {
    if (_entries != null) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final parsed = <_Icd10Entry>[];
      var start = 0;
      for (var i = 0; i < raw.length; i++) {
        if (raw.codeUnitAt(i) == 0x0A) {
          if (i > start) {
            final entry = _parseLine(raw.substring(start, i));
            if (entry != null) parsed.add(entry);
          }
          start = i + 1;
        }
      }
      if (start < raw.length) {
        final entry = _parseLine(raw.substring(start));
        if (entry != null) parsed.add(entry);
      }

      if (parsed.isEmpty) {
        _useFallback();
        return;
      }

      _entries = parsed;
      _buildIndex(parsed);
      debugPrint('Icd10DiagnosesDatabase: loaded ${parsed.length} diagnoses');
    } catch (error, stackTrace) {
      debugPrint(
          'Icd10DiagnosesDatabase: load failed, using fallback list. $error');
      debugPrint('$stackTrace');
      _useFallback();
    }
  }

  void _useFallback() {
    final fallback = ClinicalMockData.icd10Suggestions
        .map((line) => _Icd10Entry.fromDisplay(line))
        .toList();
    _entries = fallback;
    _buildIndex(fallback);
  }

  void _buildIndex(List<_Icd10Entry> entries) {
    _codeByFirstChar.clear();
    _descByFirstChar.clear();
    _displayLower = entries.map((e) => e.display.toLowerCase()).toSet();
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      _codeByFirstChar.putIfAbsent(entry.codeFirstChar, () => <int>[]).add(i);
      _descByFirstChar.putIfAbsent(entry.descFirstChar, () => <int>[]).add(i);
    }
  }

  bool isKnownDisplay(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return _displayLower?.contains(normalized) ?? false;
  }

  static _Icd10Entry? _parseLine(String raw) {
    final line = raw.trim();
    if (line.isEmpty) return null;

    if (_cmsLine.hasMatch(line)) {
      return _parseCmsLine(line);
    }

    if (line.contains(' - ')) {
      return _Icd10Entry.fromDisplay(line);
    }

    final tab = line.indexOf('\t');
    if (tab > 0) {
      return _Icd10Entry(
        line.substring(0, tab).trim(),
        line.substring(tab + 1).trim(),
      );
    }

    final match =
        RegExp(r'^([A-Za-z]\d{2}(?:\.\d+)?)\s+(.+)$').firstMatch(line);
    if (match != null) {
      return _Icd10Entry(match.group(1)!, match.group(2)!.trim());
    }

    return null;
  }

  static final _cmsLine = RegExp(r'^\d+\s+\S+\s+\d+\s+');

  static _Icd10Entry? _parseCmsLine(String line) {
    final match = RegExp(r'^\d+\s+(\S+)\s+\d+\s+(.+)$').firstMatch(line);
    if (match == null) return null;

    var description = match.group(2)!.trim();
    final duplicate = RegExp(r'^(.+?)\s{2,}.+$').firstMatch(description);
    if (duplicate != null) {
      description = duplicate.group(1)!.trim();
    }

    return _Icd10Entry(match.group(1)!, description);
  }

  List<String> search(String query, {int limit = 8}) {
    final entries = _entries;
    if (entries == null || entries.isEmpty) return const [];

    final q = query.trim();
    if (q.isEmpty) {
      return entries.take(limit).map((e) => e.display).toList();
    }

    final lower = q.toLowerCase();
    final results = <String>[];
    final seen = <String>{};

    void addEntry(_Icd10Entry entry) {
      if (!seen.add(entry.display)) return;
      results.add(entry.display);
    }

    if (_looksLikeCodeQuery(q)) {
      final bucket = _codeByFirstChar[q[0].toUpperCase()];
      if (bucket != null) {
        final codeQuery = q.toUpperCase();
        for (final index in bucket) {
          final entry = entries[index];
          if (entry.code.startsWith(codeQuery)) {
            addEntry(entry);
            if (results.length >= limit) return results;
          }
        }
      }
    }

    if (results.length < limit) {
      final bucket = _descByFirstChar[lower[0]];
      if (bucket != null) {
        for (final index in bucket) {
          final entry = entries[index];
          if (entry.descriptionLower.contains(lower) ||
              entry.code.toLowerCase().contains(lower)) {
            addEntry(entry);
            if (results.length >= limit) return results;
          }
        }
      }
    }

    return results;
  }

  static bool _looksLikeCodeQuery(String query) {
    if (query.isEmpty) return false;
    final first = query.codeUnitAt(0);
    if (first < 0x41 || (first > 0x5A && first < 0x61) || first > 0x7A) {
      return false;
    }
    return query.length == 1 || RegExp(r'^\d').hasMatch(query.substring(1, 2));
  }
}

class _Icd10Entry {
  _Icd10Entry(this.code, this.description);

  factory _Icd10Entry.fromDisplay(String display) {
    final dash = display.indexOf(' - ');
    if (dash > 0) {
      return _Icd10Entry(
        display.substring(0, dash).trim(),
        display.substring(dash + 3).trim(),
      );
    }
    return _Icd10Entry(display, display);
  }

  final String code;
  final String description;

  String get display => '$code - $description';
  String get codeFirstChar => code.isEmpty ? '#' : code[0].toUpperCase();
  String get descFirstChar =>
      description.isEmpty ? '#' : description[0].toLowerCase();
  String get descriptionLower => description.toLowerCase();
}
