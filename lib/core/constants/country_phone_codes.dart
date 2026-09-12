class CountryPhoneCode {
  const CountryPhoneCode({
    required this.country,
    required this.dialCode,
  });

  final String country;
  final String dialCode;

  String get label => '$country ($dialCode)';
}

abstract final class CountryPhoneCodes {
  static const defaultDialCode = '+91';
  static const defaultCountry = 'India';

  static const List<CountryPhoneCode> all = [
    CountryPhoneCode(country: 'India', dialCode: '+91'),
    CountryPhoneCode(country: 'Afghanistan', dialCode: '+93'),
    CountryPhoneCode(country: 'Australia', dialCode: '+61'),
    CountryPhoneCode(country: 'Bangladesh', dialCode: '+880'),
    CountryPhoneCode(country: 'Bhutan', dialCode: '+975'),
    CountryPhoneCode(country: 'Canada', dialCode: '+1'),
    CountryPhoneCode(country: 'China', dialCode: '+86'),
    CountryPhoneCode(country: 'France', dialCode: '+33'),
    CountryPhoneCode(country: 'Germany', dialCode: '+49'),
    CountryPhoneCode(country: 'Indonesia', dialCode: '+62'),
    CountryPhoneCode(country: 'Ireland', dialCode: '+353'),
    CountryPhoneCode(country: 'Italy', dialCode: '+39'),
    CountryPhoneCode(country: 'Japan', dialCode: '+81'),
    CountryPhoneCode(country: 'Malaysia', dialCode: '+60'),
    CountryPhoneCode(country: 'Maldives', dialCode: '+960'),
    CountryPhoneCode(country: 'Myanmar', dialCode: '+95'),
    CountryPhoneCode(country: 'Nepal', dialCode: '+977'),
    CountryPhoneCode(country: 'Netherlands', dialCode: '+31'),
    CountryPhoneCode(country: 'New Zealand', dialCode: '+64'),
    CountryPhoneCode(country: 'Oman', dialCode: '+968'),
    CountryPhoneCode(country: 'Pakistan', dialCode: '+92'),
    CountryPhoneCode(country: 'Qatar', dialCode: '+974'),
    CountryPhoneCode(country: 'Saudi Arabia', dialCode: '+966'),
    CountryPhoneCode(country: 'Singapore', dialCode: '+65'),
    CountryPhoneCode(country: 'South Africa', dialCode: '+27'),
    CountryPhoneCode(country: 'Sri Lanka', dialCode: '+94'),
    CountryPhoneCode(country: 'Switzerland', dialCode: '+41'),
    CountryPhoneCode(country: 'Thailand', dialCode: '+66'),
    CountryPhoneCode(country: 'United Arab Emirates', dialCode: '+971'),
    CountryPhoneCode(country: 'United Kingdom', dialCode: '+44'),
    CountryPhoneCode(country: 'United States', dialCode: '+1'),
  ];

  static CountryPhoneCode get defaultEntry => all.first;

  static CountryPhoneCode? findByDialCode(String dialCode) {
    for (final entry in all) {
      if (entry.dialCode == dialCode) return entry;
    }
    return null;
  }

  static List<CountryPhoneCode> sortedByDialCodeLengthDesc() {
    final copy = List<CountryPhoneCode>.from(all);
    copy.sort((a, b) => b.dialCode.length.compareTo(a.dialCode.length));
    return copy;
  }
}
