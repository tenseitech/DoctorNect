import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/countries.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../widgets/location_dropdown_fields.dart';

class SearchFiltersSheet extends StatefulWidget {
  const SearchFiltersSheet({
    super.key,
    this.roundedTopOnly = true,
    required this.specialityCategory,
    required this.locationFilter,
    required this.availableToday,
    required this.minRating,
    required this.language,
    required this.specialityOptions,
    required this.locationOptions,
    required this.languageOptions,
  });

  final bool roundedTopOnly;
  final String? specialityCategory;
  final String? locationFilter;
  final bool availableToday;
  final double? minRating;
  final String? language;
  final List<({String label, String categoryKey})> specialityOptions;
  final List<String> locationOptions;
  final List<String> languageOptions;

  static Future<SearchFiltersResult?> show(
    BuildContext context, {
    required String? specialityCategory,
    required String? locationFilter,
    required bool availableToday,
    required double? minRating,
    required String? language,
    required List<({String label, String categoryKey})> specialityOptions,
    required List<String> locationOptions,
    required List<String> languageOptions,
  }) {
    final isWide = MediaQuery.sizeOf(context).width >= 600;

    if (isWide) {
      return showDialog<SearchFiltersResult>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
              child: SearchFiltersSheet(
                roundedTopOnly: false,
                specialityCategory: specialityCategory,
                locationFilter: locationFilter,
                availableToday: availableToday,
                minRating: minRating,
                language: language,
                specialityOptions: specialityOptions,
                locationOptions: locationOptions,
                languageOptions: languageOptions,
              ),
            ),
          ),
        ),
      );
    }

    return showModalBottomSheet<SearchFiltersResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SearchFiltersSheet(
          roundedTopOnly: true,
          specialityCategory: specialityCategory,
          locationFilter: locationFilter,
          availableToday: availableToday,
          minRating: minRating,
          language: language,
          specialityOptions: specialityOptions,
          locationOptions: locationOptions,
          languageOptions: languageOptions,
        ),
      ),
    );
  }

  @override
  State<SearchFiltersSheet> createState() => _SearchFiltersSheetState();
}

class SearchFiltersResult {
  const SearchFiltersResult({
    this.specialityCategory,
    this.locationFilter,
    this.availableToday = false,
    this.minRating,
    this.language,
    this.cleared = false,
  });

  final String? specialityCategory;
  final String? locationFilter;
  final bool availableToday;
  final double? minRating;
  final String? language;
  final bool cleared;
}

class _SearchFiltersSheetState extends State<SearchFiltersSheet> {
  late String? _specialityCategory;
  late String? _locationFilter;
  late bool _availableToday;
  late double? _minRating;
  late String? _language;
  String? _searchCountry = Countries.defaultCountry;
  String? _searchState;
  String? _searchCity;
  bool _showCustomLocation = false;

  @override
  void initState() {
    super.initState();
    _specialityCategory = widget.specialityCategory;
    _locationFilter = widget.locationFilter;
    _availableToday = widget.availableToday;
    _minRating = widget.minRating;
    _language = widget.language;
    if (_locationFilter != null && !widget.locationOptions.contains(_locationFilter)) {
      _showCustomLocation = true;
      _searchCity = _locationFilter;
    }
  }

  void _clearAll() {
    Navigator.pop(
      context,
      const SearchFiltersResult(cleared: true),
    );
  }

  void _apply() {
    Navigator.pop(
      context,
      SearchFiltersResult(
        specialityCategory: _specialityCategory,
        locationFilter: _locationFilter,
        availableToday: _availableToday,
        minRating: _minRating,
        language: _language,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceOf(context),
      borderRadius: widget.roundedTopOnly
          ? const BorderRadius.vertical(top: Radius.circular(24))
          : BorderRadius.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.roundedTopOnly) ...[
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderOf(context),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Filters',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimaryOf(context),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _clearAll,
                  child: Text(
                    'Clear all',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _FilterSection(
                    title: 'Speciality',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: widget.specialityOptions.map((chip) {
                        final selected = _specialityCategory == chip.categoryKey;
                        return _OptionChip(
                          label: chip.label,
                          selected: selected,
                          onTap: () => setState(() {
                            _specialityCategory =
                                selected ? null : chip.categoryKey;
                          }),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _FilterSection(
                    title: 'Location',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (_locationFilter != null && !widget.locationOptions.contains(_locationFilter))
                              _OptionChip(
                                label: '📍 $_locationFilter',
                                selected: true,
                                onTap: () => setState(() {
                                  _locationFilter = null;
                                  _searchCity = null;
                                }),
                              ),
                            ...widget.locationOptions.map((city) {
                              final selected = _locationFilter == city;
                              return _OptionChip(
                                label: city,
                                selected: selected,
                                onTap: () => setState(() {
                                  _locationFilter = selected ? null : city;
                                  _searchCity = selected ? null : city;
                                }),
                              );
                            }),
                          ],
                        ),
                        const SizedBox(height: 10),
                        InkWell(
                          onTap: () => setState(() => _showCustomLocation = !_showCustomLocation),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Icon(
                                  _showCustomLocation ? Icons.keyboard_arrow_up : Icons.public,
                                  size: 18,
                                  color: AppColors.patientTeal,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _showCustomLocation
                                      ? 'Hide worldwide location picker'
                                      : 'Select other city / country...',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.patientTeal,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_showCustomLocation) ...[
                          const SizedBox(height: 10),
                          LocationDropdownFields(
                            country: _searchCountry,
                            state: _searchState,
                            city: _searchCity,
                            countryRequired: false,
                            stateRequired: false,
                            cityRequired: false,
                            usePatientFieldStyle: true,
                            onCountryChanged: (c) => setState(() {
                              _searchCountry = c;
                              _searchState = null;
                              _searchCity = null;
                            }),
                            onStateChanged: (s) => setState(() {
                              _searchState = s;
                              _searchCity = null;
                            }),
                            onCityChanged: (c) => setState(() {
                              _searchCity = c;
                              if (c != null && c.trim().isNotEmpty) {
                                _locationFilter = c.trim();
                              }
                            }),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  _FilterSection(
                    title: 'Rating',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _OptionChip(
                          label: '4★ & above',
                          selected: _minRating != null && _minRating! >= 4,
                          onTap: () => setState(() {
                            _minRating = _minRating != null && _minRating! >= 4 ? null : 4.0;
                          }),
                        ),
                        _OptionChip(
                          label: '3★ & above',
                          selected: _minRating != null && _minRating! < 4,
                          onTap: () => setState(() {
                            _minRating = _minRating != null && _minRating! < 4 ? null : 3.0;
                          }),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  _FilterSection(
                    title: 'Language',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: widget.languageOptions.map((lang) {
                        final selected = _language == lang;
                        return _OptionChip(
                          label: lang,
                          selected: selected,
                          onTap: () => setState(() {
                            _language = selected ? null : lang;
                          }),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 22),
                  _FilterSection(
                    title: 'Availability',
                    child: SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _availableToday,
                      activeThumbColor: AppColors.patientTeal,
                      title: Text(
                        'Available today',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        'Show only doctors with slots today',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.textSecondaryOf(context),
                        ),
                      ),
                      onChanged: (v) => setState(() => _availableToday = v),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: AppColors.borderOf(context)),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _apply,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.patientTeal,
                  foregroundColor: AppColors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Apply filters',
                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterSection extends StatelessWidget {
  const _FilterSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.patientTeal : AppColors.cardBgOf(context),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? AppColors.patientTeal : AppColors.borderOf(context),
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.surfaceOf(context) : AppColors.textPrimaryOf(context),
            ),
          ),
        ),
      ),
    );
  }
}
