import '../../../core/constants/speciality_mapper.dart';
import '../../../core/constants/specialty_categories.dart';
import 'package:medibond/features/patient/models/patient_models.dart';

/// Matches patient free-text queries against doctor listings across name,
/// speciality, location, experience, rating, language, and related fields.
abstract final class DoctorSearchMatcher {
  DoctorSearchMatcher._();

  static const _knownLanguages = [
    'hindi', 'english', 'marathi', 'bengali', 'telugu', 'tamil',
    'gujarati', 'kannada', 'malayalam', 'punjabi', 'urdu', 'odia',
  ];

  static const _stopWords = {
    'a', 'an', 'the', 'in', 'at', 'on', 'for', 'with', 'and', 'or', 'of', 'to',
    'doctor', 'dr', 'dr.', 'specialist', 'speciality', 'specialty', 'near', 'me',
  };

  static bool matches(DoctorListing doctor, String rawQuery) {
    final query = rawQuery.trim();
    if (query.isEmpty) return true;

    final normalized = query.toLowerCase();

    final minRating = _parseMinRating(normalized);
    if (minRating != null && doctor.rating < minRating) return false;

    final minExperience = _parseMinExperience(normalized);
    if (minExperience != null && doctor.experienceYears < minExperience) return false;

    if (_wantsAvailableToday(normalized) &&
        doctor.availability != DoctorAvailability.today) {
      return false;
    }

    if (_wantsVerified(normalized) && !doctor.verified) return false;

    final gender = _parseGender(normalized);
    if (gender != null && doctor.gender.toLowerCase() != gender) return false;

    final language = _parseLanguage(normalized);
    if (language != null &&
        !doctor.languages.any((l) => l.toLowerCase() == language)) {
      return false;
    }

    final tokens = _searchTokens(normalized);
    if (tokens.isEmpty) return true;

    final haystack = _buildHaystack(doctor);
    return tokens.every((token) => haystack.contains(token));
  }

  static int relevanceScore(DoctorListing doctor, String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) return 0;

    var score = 0;
    final name = doctor.name.toLowerCase();
    final spec = doctor.specialization.toLowerCase();

    if (name == query) score += 120;
    if (name.contains(query)) score += 80;
    if (spec == query) score += 70;
    if (spec.contains(query)) score += 50;

    for (final token in _searchTokens(query)) {
      if (name.contains(token)) score += 24;
      if (spec.contains(token)) score += 18;
      if (doctor.clinicName.toLowerCase().contains(token)) score += 12;
      if (doctor.area.toLowerCase().contains(token)) score += 12;
      if (doctor.languages.any((l) => l.toLowerCase().contains(token))) score += 10;
      if (doctor.qualification.toLowerCase().contains(token)) score += 8;
      if ('${doctor.experienceYears}'.contains(token)) score += 6;
      if (doctor.rating.toStringAsFixed(1).contains(token)) score += 6;
    }

    score += (doctor.rating * 4).round();
    score -= (doctor.distanceKm * 2).round();
    if (doctor.verified) score += 4;
    if (doctor.availability == DoctorAvailability.today) score += 6;
    return score;
  }

  static List<String> _searchTokens(String normalizedQuery) {
    var withoutPatterns = normalizedQuery
        .replaceAll(RegExp(r'\b\d+(?:\.\d+)?\s*(?:\+|\*)?\s*(?:star|stars|rating|★)\b'), ' ')
        .replaceAll(RegExp(r'\b(?:rating|stars?)\s*\d+(?:\.\d+)?\b'), ' ')
        .replaceAll(RegExp(r'\b\d+\s*(?:\+|\s*)?(?:years?|yrs?|y\.?o\.?|exp(?:erience)?)\b'), ' ')
        .replaceAll(RegExp(r'\b(?:available|open)\s+today\b'), ' ')
        .replaceAll(RegExp(r'\btoday\s+(?:available|open)\b'), ' ')
        .replaceAll(RegExp(r'\bverified\b'), ' ')
        .replaceAll(RegExp(r'\b(?:male|female)\b'), ' ')
        .replaceAll(RegExp(r'\b(?:male|female)\s+(?:doctor|dr)\b'), ' ')
        .replaceAll(RegExp(r'\bspeaks?\s+\w+\b'), ' ');

    for (final lang in _knownLanguages) {
      withoutPatterns = withoutPatterns.replaceAll(RegExp('\\b$lang\\b'), ' ');
    }

    return withoutPatterns
        .split(RegExp(r'[\s,]+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty && t.length > 1 && !_stopWords.contains(t))
        .toList();
  }

  static String _buildHaystack(DoctorListing doctor) {
    final parts = <String>[
      doctor.name,
      'dr ${doctor.name}',
      doctor.specialization,
      SpecialityMapper.toBackendSpeciality(doctor.specialization),
      doctor.qualification,
      doctor.clinicName,
      doctor.city,
      doctor.area,
      doctor.addressLine1,
      doctor.state,
      doctor.locationLabel,
      doctor.gender,
      ...doctor.languages,
      '${doctor.experienceYears}',
      '${doctor.experienceYears} years',
      '${doctor.experienceYears} yrs',
      doctor.rating.toStringAsFixed(1),
      doctor.rating.toStringAsFixed(0),
      '${doctor.reviewCount}',
      '${doctor.reviewCount} reviews',
      if (doctor.verified) 'verified',
      _availabilityLabel(doctor.availability),
      doctor.nextSlot,
    ];

    for (final entry in specialtyCategories.entries) {
      for (final alias in entry.value) {
        if (_doctorMatchesSpec(doctor.specialization, alias)) {
          parts.add(entry.key);
          parts.addAll(entry.value);
          break;
        }
      }
    }

    return parts.join(' ').toLowerCase();
  }

  static bool _doctorMatchesSpec(String doctorSpec, String filterSpec) {
    final backend = SpecialityMapper.toBackendSpeciality(filterSpec);
    return doctorSpec == backend ||
        doctorSpec == filterSpec ||
        SpecialityMapper.toBackendSpeciality(doctorSpec) == backend;
  }

  static double? _parseMinRating(String query) {
    final patterns = [
      RegExp(r'(\d(?:\.\d)?)\s*(?:\+|\*)?\s*(?:star|stars|rating|★)'),
      RegExp(r'(?:rating|stars?)\s*(\d(?:\.\d)?)'),
      RegExp(r'(\d(?:\.\d)?)\s*★'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(query);
      if (match != null) {
        return double.tryParse(match.group(1)!);
      }
    }
    return null;
  }

  static int? _parseMinExperience(String query) {
    final patterns = [
      RegExp(r'(\d+)\s*(?:\+|\s*)?(?:years?|yrs?|y\.?o\.?)\s*(?:exp(?:erience)?)?'),
      RegExp(r'(\d+)\s*(?:\+|\s*)?(?:exp(?:erience)?|experience)'),
      RegExp(r'(?:exp(?:erience)?|experience)\s*(\d+)'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(query);
      if (match != null) {
        return int.tryParse(match.group(1)!);
      }
    }
    return null;
  }

  static bool _wantsAvailableToday(String query) {
    return RegExp(r'\b(?:available|open)\s+today\b').hasMatch(query) ||
        RegExp(r'\btoday\s+(?:available|open|slot)\b').hasMatch(query);
  }

  static bool _wantsVerified(String query) {
    return RegExp(r'\bverified\b').hasMatch(query);
  }

  static String? _parseGender(String query) {
    if (RegExp(r'\bfemale\b').hasMatch(query)) return 'female';
    if (RegExp(r'\bmale\b').hasMatch(query)) return 'male';
    return null;
  }

  static String? _parseLanguage(String query) {
    final speakMatch = RegExp(r'\bspeaks?\s+(\w+)\b').firstMatch(query);
    if (speakMatch != null) return speakMatch.group(1)!.toLowerCase();

    for (final lang in _knownLanguages) {
      if (RegExp('\\b$lang\\b').hasMatch(query)) return lang;
    }
    return null;
  }

  static String _availabilityLabel(DoctorAvailability availability) {
    return switch (availability) {
      DoctorAvailability.today => 'available today today',
      DoctorAvailability.tomorrow => 'available tomorrow tomorrow',
      DoctorAvailability.later => 'later available',
    };
  }
}
