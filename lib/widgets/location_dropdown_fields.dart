import 'package:flutter/material.dart';

import '../core/constants/app_constants.dart';
import '../core/constants/countries.dart';
import '../core/constants/world_locations.dart';
import '../core/theme/app_colors.dart';
import '../core/validators/form_validators.dart';
import 'required_field_label.dart';
import 'searchable_dropdown_form_field.dart';

class LocationDropdownFields extends StatelessWidget {
  const LocationDropdownFields({
    super.key,
    required this.country,
    required this.state,
    required this.city,
    required this.onCountryChanged,
    required this.onStateChanged,
    required this.onCityChanged,
    this.countryRequired = true,
    this.stateRequired = true,
    this.cityRequired = true,
    this.usePatientFieldStyle = false,
  });

  final String? country;
  final String? state;
  final String? city;
  final ValueChanged<String?> onCountryChanged;
  final ValueChanged<String?> onStateChanged;
  final ValueChanged<String?> onCityChanged;
  final bool countryRequired;
  final bool stateRequired;
  final bool cityRequired;
  final bool usePatientFieldStyle;

  String get _effectiveCountry {
    final current = country?.trim();
    if (current != null && current.isNotEmpty) return current;
    return Countries.defaultCountry;
  }

  List<String> get _countryOptions {
    final current = _effectiveCountry;
    if (!Countries.all.contains(current)) {
      return [current, ...Countries.all];
    }
    return Countries.all;
  }

  bool get _hasLocationData {
    return WorldLocations.hasData(_effectiveCountry);
  }

  List<String> get _stateOptions {
    return WorldLocations.statesWithLegacy(_effectiveCountry, state);
  }

  List<String> get _cityOptions {
    final selectedCountry = _effectiveCountry;
    final selectedState = state?.trim();
    if (selectedState == null || selectedState.isEmpty) {
      return const [];
    }
    final options =
        WorldLocations.citiesWithLegacy(selectedCountry, selectedState, city);
    return [...options]
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  InputDecoration _decoration(BuildContext context, String label,
      {String? hint, bool isRequired = false}) {
    if (!usePatientFieldStyle) {
      return RequiredFieldLabels.decorate(
        InputDecoration(hintText: hint),
        label,
        isRequired: isRequired,
      );
    }
    return RequiredFieldLabels.decorate(
      InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppColors.cardBgOf(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.inputRadius),
          borderSide: BorderSide(color: AppColors.borderOf(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConstants.inputRadius),
          borderSide: BorderSide(color: AppColors.borderOf(context)),
        ),
      ),
      label,
      isRequired: isRequired,
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveCountry = _effectiveCountry;
    final selectedCountry =
        _countryOptions.contains(effectiveCountry) ? effectiveCountry : null;
    final selectedState =
        state != null && _stateOptions.contains(state) ? state : null;
    final selectedCity =
        city != null && _cityOptions.contains(city) ? city : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchableDropdownFormField(
          key: ValueKey('country-$effectiveCountry'),
          title: 'Country',
          value: selectedCountry,
          items: _countryOptions,
          decoration:
              _decoration(context, 'Country', isRequired: countryRequired),
          hintText: 'Select country',
          validator: countryRequired
              ? (v) => FormValidators.dropdown(v, field: 'Country')
              : null,
          onChanged: onCountryChanged,
        ),
        const SizedBox(height: 12),
        if (_hasLocationData) ...[
          SearchableDropdownFormField(
            key: ValueKey('state-$effectiveCountry'),
            title: 'State',
            value: selectedState,
            items: _stateOptions,
            decoration:
                _decoration(context, 'State', isRequired: stateRequired),
            hintText: 'Select state',
            validator: stateRequired
                ? (v) => FormValidators.dropdown(v, field: 'State')
                : null,
            onChanged: onStateChanged,
          ),
          const SizedBox(height: 12),
          SearchableDropdownFormField(
            key: ValueKey('city-$effectiveCountry-$state'),
            title: 'City',
            value: selectedCity,
            items: _cityOptions,
            decoration: _decoration(context, 'City', isRequired: cityRequired),
            hintText: state == null || state!.trim().isEmpty
                ? 'Select state first'
                : 'Select city',
            validator: cityRequired
                ? (v) => FormValidators.dropdown(v, field: 'City')
                : null,
            enabled: state != null && state!.trim().isNotEmpty,
            onChanged: onCityChanged,
          ),
        ],
      ],
    );
  }
}
