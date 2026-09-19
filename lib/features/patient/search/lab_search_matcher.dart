import '../../patient/lab/models/lab_models.dart';
import '../data/patient_favorites_store.dart';

abstract final class LabSearchMatcher {
  LabSearchMatcher._();

  static const _stopWords = {
    'a',
    'an',
    'the',
    'in',
    'at',
    'on',
    'for',
    'with',
    'and',
    'or',
    'of',
    'to',
    'lab',
    'labs',
    'test',
    'tests',
    'package',
    'packages',
    'diagnostic',
    'diagnostics',
  };

  static bool matchesTest(LabTestItem test, String rawQuery) {
    return _matchesHaystack(_testHaystack(test), rawQuery);
  }

  static bool matchesPackage(LabHealthPackage package, String rawQuery) {
    return _matchesHaystack(_packageHaystack(package), rawQuery);
  }

  static bool matchesPartnerLab(PartnerLab lab, String rawQuery) {
    return _matchesHaystack(_partnerLabHaystack(lab), rawQuery);
  }

  static bool matchesSavedLab(SavedLabEntry lab, String rawQuery) {
    return _matchesHaystack(_savedLabHaystack(lab), rawQuery);
  }

  static int relevanceScoreTest(LabTestItem test, String rawQuery) {
    return _score(
        _testHaystack(test), test.name, rawQuery, test.popular ? 8 : 0);
  }

  static int relevanceScorePackage(LabHealthPackage package, String rawQuery) {
    return _score(_packageHaystack(package), package.name, rawQuery, 4);
  }

  static int relevanceScorePartnerLab(PartnerLab lab, String rawQuery) {
    return _score(_partnerLabHaystack(lab), lab.name, rawQuery, 0);
  }

  static int relevanceScoreSavedLab(SavedLabEntry lab, String rawQuery) {
    return _score(_savedLabHaystack(lab), lab.name, rawQuery, 0);
  }

  static String _testHaystack(LabTestItem test) {
    return [
      test.name,
      test.category,
      test.sampleType.name,
      ...test.parameters,
      if (test.fastingRequired) 'fasting',
      '${test.reportHours}h report',
      if (test.popular) 'popular',
    ].whereType<String>().join(' ').toLowerCase();
  }

  static String _packageHaystack(LabHealthPackage package) {
    return [
      package.name,
      package.description,
      '${package.testCount} tests',
      'health package package',
    ].join(' ').toLowerCase();
  }

  static String _partnerLabHaystack(PartnerLab lab) {
    return [lab.name, lab.area, 'lab diagnostic'].join(' ').toLowerCase();
  }

  static String _savedLabHaystack(SavedLabEntry lab) {
    return [lab.name, lab.area, 'lab diagnostic'].join(' ').toLowerCase();
  }

  static bool _matchesHaystack(String haystack, String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) return false;

    final tokens = _searchTokens(query);
    if (tokens.isEmpty) return haystack.contains(query);
    return tokens.every((token) => haystack.contains(token));
  }

  static int _score(
      String haystack, String primaryName, String rawQuery, int bonus) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) return 0;

    var score = bonus;
    final name = primaryName.toLowerCase();

    if (name == query) score += 100;
    if (name.contains(query)) score += 60;

    for (final token in _searchTokens(query)) {
      if (name.contains(token)) score += 20;
      if (haystack.contains(token)) score += 10;
    }
    return score;
  }

  static List<String> _searchTokens(String normalizedQuery) {
    return normalizedQuery
        .split(RegExp(r'[\s,]+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty && t.length > 1 && !_stopWords.contains(t))
        .toList();
  }
}
