import 'indian_cities.dart';
import 'world_locations_data.dart';

/// States / provinces and cities for every supported [Countries.all] entry.
abstract final class WorldLocations {
  static Map<String, Map<String, List<String>>> get _data => {
        'India': IndianCities.byState,
        ...WorldLocationsData.byCountry,
      };

  static bool hasData(String country) {
    final regions = _data[country];
    return regions != null && regions.isNotEmpty;
  }

  static List<String> statesFor(String country) {
    final regions = _data[country];
    if (regions == null || regions.isEmpty) return const [];
    return regions.keys.toList();
  }

  static List<String> citiesFor(String country, String state) {
    final regions = _data[country];
    if (regions == null) return const [];
    final list = List<String>.from(regions[state] ?? const []);
    list.sort((a, b) => a.compareTo(b));
    return list;
  }

  static List<String> statesWithLegacy(String country, String? legacy) {
    final base = statesFor(country);
    final value = legacy?.trim();
    if (value == null || value.isEmpty || base.contains(value)) return base;
    return [value, ...base];
  }

  static List<String> citiesWithLegacy(String country, String state, String? legacy) {
    final base = citiesFor(country, state);
    final value = legacy?.trim();
    if (value == null || value.isEmpty || base.contains(value)) return base;
    final list = [value, ...base];
    list.sort((a, b) => a.compareTo(b));
    return list;
  }

  static String postalCodeLabel(String country) {
    switch (country) {
      case 'India':
        return 'Pincode';
      case 'United States':
        return 'ZIP code';
      case 'United Kingdom':
        return 'Postcode';
      default:
        return 'Postal / ZIP code';
    }
  }
}
