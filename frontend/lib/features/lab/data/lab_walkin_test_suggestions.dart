import '../../doctor/clinical/data/medical_tests_catalog.dart';

/// Master test names for Walk-in Patient test autocomplete (pathology + radiology + body parts).
abstract final class LabWalkInTestSuggestions {
  static final List<String> all = _build();

  static List<String> _build() {
    final seen = <String>{};
    final names = <String>[];

    void add(String name) {
      final trimmed = name.trim();
      final key = trimmed.toLowerCase();
      if (key.isEmpty || !seen.add(key)) return;
      names.add(trimmed);
    }

    for (final item in MedicalTestsCatalog.labTests) {
      add(item.name);
    }
    for (final item in MedicalTestsCatalog.radiologyTests) {
      add(item.name);
    }
    for (final part in MedicalTestsCatalog.bodyParts) {
      add(part);
    }

    names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return names;
  }

  static List<String> matching(String query, {int limit = 8}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];

    return all
        .where((name) => name.toLowerCase().contains(q))
        .take(limit)
        .toList();
  }
}
