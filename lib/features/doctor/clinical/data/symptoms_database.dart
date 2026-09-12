import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'clinical_mock_data.dart';

class SymptomCatalogEntry {
  const SymptomCatalogEntry({
    required this.code,
    required this.displayName,
    required this.searchTerms,
  });

  final String code;
  final String displayName;
  final List<String> searchTerms;
}

/// Loads symptom options from bundled catalog + country follow-up/case lists.
class SymptomsDatabase extends ChangeNotifier {
  SymptomsDatabase._();

  static final SymptomsDatabase instance = SymptomsDatabase._();

  static const catalogAssetPath = 'assets/data/symptoms.json';
  static const listsAssetPath = 'assets/data/symptom_lists.json';

  List<SymptomCatalogEntry>? _entries;
  Future<void>? _loading;

  bool get isLoaded => _entries != null;

  List<String> get allDisplayNames =>
      _entries?.map((e) => e.displayName).toList() ?? const [];

  Future<void> ensureLoaded() {
    if (_entries != null) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final catalog = await _loadCatalogEntries(catalogAssetPath);
      Set<String> listCodes = const {};
      try {
        listCodes = await _loadListCodes(listsAssetPath);
      } catch (error) {
        debugPrint('SymptomsDatabase: lists asset skipped. $error');
      }

      final byCode = <String, SymptomCatalogEntry>{
        for (final entry in catalog) entry.code: entry,
      };

      for (final code in listCodes) {
        if (byCode.containsKey(code)) continue;
        final displayName = _codeToDisplayName(code);
        byCode[code] = SymptomCatalogEntry(
          code: code,
          displayName: displayName,
          searchTerms: [code.toLowerCase(), displayName.toLowerCase()],
        );
      }

      if (byCode.isEmpty) {
        _useFallback();
        return;
      }

      final merged = byCode.values.toList()
        ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      _entries = merged;
      debugPrint(
        'SymptomsDatabase: loaded ${merged.length} symptoms '
        '(catalog ${catalog.length}, lists ${listCodes.length})',
      );
    } catch (error, stackTrace) {
      debugPrint('SymptomsDatabase: load failed, using fallback list. $error');
      debugPrint('$stackTrace');
      _useFallback();
    } finally {
      notifyListeners();
    }
  }

  Future<List<SymptomCatalogEntry>> _loadCatalogEntries(String path) async {
    final raw = await rootBundle.loadString(path);
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];

    final parsed = <SymptomCatalogEntry>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final entry = _parseCatalogEntry(item.cast<String, dynamic>());
      if (entry != null) parsed.add(entry);
    }
    return parsed;
  }

  Future<Set<String>> _loadListCodes(String path) async {
    final raw = await rootBundle.loadString(path);
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const {};

    final codes = <String>{};
    for (final item in decoded) {
      if (item is! Map) continue;
      final map = item.cast<String, dynamic>();
      for (final field in ['followUp', 'case']) {
        final values = map[field];
        if (values is! List) continue;
        for (final value in values) {
          final code = (value as String?)?.trim();
          if (code != null && code.isNotEmpty) codes.add(code);
        }
      }
    }
    return codes;
  }

  void _useFallback() {
    _entries = ClinicalMockData.symptomSuggestions
        .map(
          (name) => SymptomCatalogEntry(
            code: name.toLowerCase().replaceAll(' ', '_'),
            displayName: name,
            searchTerms: [name.toLowerCase()],
          ),
        )
        .toList();
  }

  SymptomCatalogEntry? _parseCatalogEntry(Map<String, dynamic> item) {
    final code = (item['code'] as String?)?.trim() ?? '';
    final name = _titleCase((item['name'] as String?)?.trim() ?? '');
    if (name.isEmpty) return null;

    final terms = <String>{name.toLowerCase(), code.toLowerCase()};
    final synonyms = item['synonyms'];
    if (synonyms is List) {
      for (final s in synonyms) {
        final syn = (s as String?)?.trim();
        if (syn != null && syn.isNotEmpty) {
          terms.add(syn.toLowerCase());
          terms.add(_titleCase(syn).toLowerCase());
        }
      }
    }

    return SymptomCatalogEntry(
      code: code.isEmpty ? name.toLowerCase().replaceAll(' ', '_') : code,
      displayName: name,
      searchTerms: terms.toList(),
    );
  }

  static String _titleCase(String raw) {
    if (raw.isEmpty) return raw;
    return raw.split(RegExp(r'\s+')).map((word) {
      if (word.isEmpty) return word;
      if (word.length == 1) return word.toUpperCase();
      return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
    }).join(' ');
  }

  static String _codeToDisplayName(String code) {
    return _titleCase(code.replaceAll('_', ' '));
  }

  List<String> search(String query) {
    final entries = _entries;
    if (entries == null || entries.isEmpty) {
      return _fallbackSearch(query);
    }

    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return entries.map((e) => e.displayName).toList();
    }

    return entries
        .where((e) => e.searchTerms.any((term) => term.contains(q)))
        .map((e) => e.displayName)
        .toList();
  }

  List<String> _fallbackSearch(String query) {
    final list = ClinicalMockData.symptomSuggestions;
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return List<String>.from(list);
    return list.where((s) => s.toLowerCase().contains(q)).toList();
  }
}
