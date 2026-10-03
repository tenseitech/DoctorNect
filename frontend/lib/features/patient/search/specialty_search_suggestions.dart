import '../../../core/constants/specialty_categories.dart';

class SpecialtySearchSuggestion {
  const SpecialtySearchSuggestion({
    required this.label,
    required this.categoryKey,
    this.subtitle,
    this.isCategory = false,
  });

  final String label;
  final String categoryKey;
  final String? subtitle;
  final bool isCategory;
}

abstract final class SpecialtySearchSuggestions {
  SpecialtySearchSuggestions._();

  static const _defaultCategoryKeys = [
    'General Physician',
    'Heart Specialist',
    'Skin Specialist',
    'Child Care',
    'Bone & Joint',
    'Ear, Nose & Throat',
    "Women's Health",
    'Neurologist',
  ];

  static List<SpecialtySearchSuggestion> forQuery(
    String rawQuery, {
    bool showDefaultsWhenEmpty = false,
    int limit = 8,
  }) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) {
      if (!showDefaultsWhenEmpty) return const [];
      return [
        for (final key in _defaultCategoryKeys)
          if (specialtyCategories.containsKey(key))
            SpecialtySearchSuggestion(
              label: key,
              categoryKey: key,
              subtitle: 'Speciality',
              isCategory: true,
            ),
      ].take(limit).toList();
    }

    final scored = <({SpecialtySearchSuggestion item, int score})>[];

    for (final entry in specialtyCategories.entries) {
      final category = entry.key;
      final categoryLower = category.toLowerCase();

      final categoryScore = _scoreMatch(categoryLower, query);
      if (categoryScore > 0) {
        scored.add((
          item: SpecialtySearchSuggestion(
            label: category,
            categoryKey: category,
            subtitle: 'Speciality category',
            isCategory: true,
          ),
          score: categoryScore + 20,
        ));
      }

      for (final spec in entry.value) {
        final specLower = spec.toLowerCase();
        final specScore = _scoreMatch(specLower, query);
        if (specScore <= 0) continue;

        scored.add((
          item: SpecialtySearchSuggestion(
            label: spec,
            categoryKey: category,
            subtitle: category,
            isCategory: false,
          ),
          score: specScore,
        ));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));

    final results = <SpecialtySearchSuggestion>[];
    final seen = <String>{};
    for (final entry in scored) {
      final key = '${entry.item.categoryKey}|${entry.item.label}';
      if (!seen.add(key)) continue;
      results.add(entry.item);
      if (results.length >= limit) break;
    }
    return results;
  }

  static int _scoreMatch(String text, String query) {
    if (text == query) return 100;
    if (text.startsWith(query)) return 80;
    if (text.contains(query)) return 50;

    final tokens = query.split(RegExp(r'\s+')).where((t) => t.length > 1);
    var tokenHits = 0;
    for (final token in tokens) {
      if (text.contains(token)) tokenHits++;
    }
    if (tokenHits == 0) return 0;
    return 30 + tokenHits * 10;
  }
}
