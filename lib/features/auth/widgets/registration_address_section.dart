import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/countries.dart';
import '../../../core/constants/world_locations.dart';
import '../../../core/services/location_service.dart';
import '../../../core/validators/form_validators.dart';
import '../../../widgets/location_dropdown_fields.dart';
import 'auth_login_page_shell.dart';

class RegistrationAddressSection extends StatefulWidget {
  const RegistrationAddressSection({
    super.key,
    required this.onCountryChanged,
    required this.onStateChanged,
    required this.onCityChanged,
    required this.address1Controller,
    required this.address2Controller,
    required this.pinCodeController,
    required this.accentColor,
    this.initialCountry,
    this.initialState,
    this.initialCity,
  });

  final ValueChanged<String?> onCountryChanged;
  final ValueChanged<String?> onStateChanged;
  final ValueChanged<String?> onCityChanged;
  final TextEditingController address1Controller;
  final TextEditingController address2Controller;
  final TextEditingController pinCodeController;
  final Color accentColor;

  final String? initialCountry;
  final String? initialState;
  final String? initialCity;

  @override
  State<RegistrationAddressSection> createState() =>
      _RegistrationAddressSectionState();
}

class _RegistrationAddressSectionState
    extends State<RegistrationAddressSection> {
  bool _fetchingLocation = false;

  Future<void> _fetchCurrentLocation() async {
    if (_fetchingLocation) return;
    setState(() => _fetchingLocation = true);

    try {
      final result = await LocationService.getCurrentLocation(
        context: context,
        showToast: true,
      );

      if (result != null && mounted) {
        setState(() {
          if (result.pincode != null && result.pincode!.isNotEmpty) {
            widget.pinCodeController.text = result.pincode!;
          }
          if (result.addressLine1 != null && result.addressLine1!.isNotEmpty) {
            widget.address1Controller.text = result.addressLine1!;
          }
          if (result.addressLine2 != null && result.addressLine2!.isNotEmpty) {
            widget.address2Controller.text = result.addressLine2!;
          }

          if (result.country != null && result.country!.isNotEmpty) {
            widget.onCountryChanged(result.country);
          }
          if (result.state != null && result.state!.isNotEmpty) {
            widget.onStateChanged(result.state);
          }
          if (result.city != null && result.city!.isNotEmpty) {
            widget.onCityChanged(result.city);
          }
        });
      }
    } finally {
      if (mounted) setState(() => _fetchingLocation = false);
    }
  }

  InputDecoration _decor(String label, {bool isRequired = true}) {
    return authLoginInputDecoration(
      context: context,
      accentColor: widget.accentColor,
      labelText: label,
      isRequired: isRequired,
    );
  }

  String get _selectedCountry =>
      widget.initialCountry ?? Countries.defaultCountry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _fetchingLocation ? null : _fetchCurrentLocation,
          style: OutlinedButton.styleFrom(
            foregroundColor: widget.accentColor,
            side: BorderSide(color: widget.accentColor.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: _fetchingLocation
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: widget.accentColor),
                )
              : const Icon(Icons.my_location_outlined, size: 20),
          label: Text(
            _fetchingLocation ? 'Fetching location...' : 'Use current location',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 14),
        LocationDropdownFields(
          country: widget.initialCountry,
          state: widget.initialState,
          city: widget.initialCity,
          onCountryChanged: widget.onCountryChanged,
          onStateChanged: widget.onStateChanged,
          onCityChanged: widget.onCityChanged,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: widget.pinCodeController,
          decoration: _decor(WorldLocations.postalCodeLabel(_selectedCountry)),
          keyboardType: _selectedCountry.toLowerCase() == 'india' ? TextInputType.number : TextInputType.text,
          textInputAction: TextInputAction.next,
          inputFormatters: _selectedCountry.toLowerCase() == 'india'
              ? [
                  LengthLimitingTextInputFormatter(6),
                  FilteringTextInputFormatter.digitsOnly,
                ]
              : [
                  LengthLimitingTextInputFormatter(10),
                ],
          validator: (v) => FormValidators.pincode(v, country: _selectedCountry),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: widget.address1Controller,
          decoration: _decor('Address Line 1'),
          textInputAction: TextInputAction.next,
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Enter address line 1' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: widget.address2Controller,
          decoration: _decor('Address Line 2', isRequired: false),
          textInputAction: TextInputAction.done,
        ),
      ],
    );
  }
}