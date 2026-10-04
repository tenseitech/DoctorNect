import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:medibond/features/doctor/clinical/data/icd10_diagnoses_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'ICD-10 gz loader matches old raw parsing in entry count and search results',
    () async {
      final rawFile = File('assets/data/icd10_diagnoses.txt');
      expect(rawFile.existsSync(), isTrue);

      final raw = await rawFile.readAsString();
      final oldEntries = <_OldIcd10Entry>[];
      var start = 0;
      for (var i = 0; i < raw.length; i++) {
        if (raw.codeUnitAt(i) == 0x0A) {
          if (i > start) {
            final entry = _parseLineOld(raw.substring(start, i));
            if (entry != null) oldEntries.add(entry);
          }
          start = i + 1;
        }
      }
      if (start < raw.length) {
        final entry = _parseLineOld(raw.substring(start));
        if (entry != null) oldEntries.add(entry);
      }

      // Build old index exactly as old Icd10DiagnosesDatabase did
      final oldIndex = _OldIcd10Index(oldEntries);

      // Ensure new .gz loader is loaded
      await Icd10DiagnosesDatabase.instance.ensureLoaded();
      expect(Icd10DiagnosesDatabase.instance.isLoaded, isTrue);

      // 1. Assert identical entry count
      expect(
        Icd10DiagnosesDatabase.instance.entryCount,
        equals(oldEntries.length),
        reason: 'Entry count must match between old raw parsing and new .gz loader',
      );
      expect(oldEntries.length, greaterThan(1000));

      // 2. Assert identical results for 10 sample queries
      const sampleQueries = [
        'J06',
        'A00',
        'Cholera',
        'diabetes',
        'hypertension',
        'fever',
        'cough',
        'I10',
        'E11',
        'asthma',
      ];

      for (final query in sampleQueries) {
        final oldResults = oldIndex.search(query, limit: 8);
        final newResults = Icd10DiagnosesDatabase.instance.search(query, limit: 8);

        expect(
          newResults,
          equals(oldResults),
          reason: 'Search results for "$query" must be identical',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

class _OldIcd10Entry {
  _OldIcd10Entry(this.code, this.description);

  factory _OldIcd10Entry.fromDisplay(String display) {
    final dash = display.indexOf(' - ');
    if (dash > 0) {
      return _OldIcd10Entry(
        display.substring(0, dash).trim(),
        display.substring(dash + 3).trim(),
      );
    }
    return _OldIcd10Entry(display, display);
  }

  final String code;
  final String description;

  String get display => '$code - $description';
  String get codeFirstChar => code.isEmpty ? '#' : code[0].toUpperCase();
  String get descFirstChar =>
      description.isEmpty ? '#' : description[0].toLowerCase();
  String get descriptionLower => description.toLowerCase();
}

final _cmsLine = RegExp(r'^\d+\s+\S+\s+\d+\s+');

_OldIcd10Entry? _parseLineOld(String raw) {
  final line = raw.trim();
  if (line.isEmpty) return null;

  if (_cmsLine.hasMatch(line)) {
    final match = RegExp(r'^\d+\s+(\S+)\s+\d+\s+(.+)$').firstMatch(line);
    if (match == null) return null;

    var description = match.group(2)!.trim();
    final duplicate = RegExp(r'^(.+?)\s{2,}.+$').firstMatch(description);
    if (duplicate != null) {
      description = duplicate.group(1)!.trim();
    }

    return _OldIcd10Entry(match.group(1)!, description);
  }

  if (line.contains(' - ')) {
    return _OldIcd10Entry.fromDisplay(line);
  }

  final tab = line.indexOf('\t');
  if (tab > 0) {
    return _OldIcd10Entry(
      line.substring(0, tab).trim(),
      line.substring(tab + 1).trim(),
    );
  }

  final match = RegExp(r'^([A-Za-z]\d{2}(?:\.\d+)?)\s+(.+)$').firstMatch(line);
  if (match != null) {
    return _OldIcd10Entry(match.group(1)!, match.group(2)!.trim());
  }

  return null;
}

class _OldIcd10Index {
  _OldIcd10Index(this.entries) {
    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      _codeByFirstChar.putIfAbsent(entry.codeFirstChar, () => <int>[]).add(i);
      _descByFirstChar.putIfAbsent(entry.descFirstChar, () => <int>[]).add(i);
    }
  }

  final List<_OldIcd10Entry> entries;
  final Map<String, List<int>> _codeByFirstChar = {};
  final Map<String, List<int>> _descByFirstChar = {};

  List<String> search(String query, {int limit = 8}) {
    if (entries.isEmpty) return const [];

    final q = query.trim();
    if (q.isEmpty) {
      return entries.take(limit).map((e) => e.display).toList();
    }

    final lower = q.toLowerCase();
    final results = <String>[];
    final seen = <String>{};

    void addEntry(_OldIcd10Entry entry) {
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
