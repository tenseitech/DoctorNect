import '../../../../core/notifications/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/countries.dart';
import '../../../../core/constants/world_locations.dart';
import '../../../../core/layout/responsive_layout.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/validators/form_validators.dart';
import '../../../../widgets/location_dropdown_fields.dart';
import '../../../../widgets/required_field_label.dart';
import '../../profile/data/patient_profile_mock.dart';
import '../../profile/models/patient_profile_models.dart';
import '../../../../core/theme/app_typography.dart';

class PatientAddressSheet extends StatefulWidget {
  const PatientAddressSheet({super.key});

  static Future<bool> show(BuildContext context) {
    final wide = !ResponsiveLayout.isCompact(context);

    if (wide) {
      return showDialog<bool>(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: const PatientAddressSheet(),
          ),
        ),
      ).then((value) => value ?? false);
    }

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: const PatientAddressSheet(),
      ),
    ).then((value) => value ?? false);
  }

  @override
  State<PatientAddressSheet> createState() => _PatientAddressSheetState();
}

class _PatientAddressSheetState extends State<PatientAddressSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _line1Controller;
  late final TextEditingController _line2Controller;
  late final TextEditingController _pincodeController;
  late final TextEditingController _landmarkController;
  String? _country;
  String? _state;
  String? _city;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final address = PatientProfileMock.profileAddress;
    _line1Controller = TextEditingController(text: address.addressLine1);
    _line2Controller = TextEditingController(text: address.addressLine2);
    _pincodeController = TextEditingController(text: address.pincode);
    _landmarkController = TextEditingController(text: address.landmark);
    _country = address.country.trim().isNotEmpty
        ? address.country.trim()
        : Countries.defaultCountry;
    _state = address.state.trim().isNotEmpty ? address.state.trim() : null;
    _city = address.city.trim().isNotEmpty ? address.city.trim() : null;
  }

  @override
  void dispose() {
    _line1Controller.dispose();
    _line2Controller.dispose();
    _pincodeController.dispose();
    _landmarkController.dispose();
    super.dispose();
  }

  String? _validatePincode(String? value) {
    final label =
        WorldLocations.postalCodeLabel(_country ?? Countries.defaultCountry);
    final err = FormValidators.required(value, field: label);
    if (err != null) return err;
    if ((_country ?? Countries.defaultCountry) == Countries.defaultCountry) {
      return FormValidators.pincodeIndia(value);
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      await PatientProfileMock.updateProfileAddress(
        PatientAddress(
          addressLine1: _line1Controller.text.trim(),
          addressLine2: _line2Controller.text.trim(),
          country: _country?.trim() ?? Countries.defaultCountry,
          city: _city?.trim() ?? '',
          state: _state?.trim() ?? '',
          pincode: _pincodeController.text.trim(),
          landmark: _landmarkController.text.trim(),
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      AppToast.info(context, 'Could not save address. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final postalLabel =
        WorldLocations.postalCodeLabel(_country ?? Countries.defaultCountry);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Change location',
                      style: GoogleFonts.inter(
                        fontSize: AppTypography.headlineSmall,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed:
                        _submitting ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              Text(
                'Enter your full address for home visits, lab collection, and nearby doctor search.',
                style: GoogleFonts.inter(
                    fontSize: AppTypography.bodySmall,
                    color: AppColors.textSecondaryOf(context),
                    height: 1.4),
              ),
              const SizedBox(height: 20),
              _field(
                controller: _line1Controller,
                label: 'House / Flat no. & Street',
                hint: 'e.g. 12, MG Road',
                validator: (v) =>
                    FormValidators.required(v, field: 'Address line 1'),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              _field(
                controller: _line2Controller,
                label: 'Area / Locality',
                hint: 'e.g. Civil Lines',
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              LocationDropdownFields(
                country: _country,
                state: _state,
                city: _city,
                usePatientFieldStyle: true,
                onCountryChanged: (value) {
                  setState(() {
                    _country = value;
                    _state = null;
                    _city = null;
                  });
                },
                onStateChanged: (value) {
                  setState(() {
                    _state = value;
                    _city = null;
                  });
                },
                onCityChanged: (value) => setState(() => _city = value),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _field(
                      controller: _pincodeController,
                      label: postalLabel,
                      keyboardType: TextInputType.number,
                      validator: _validatePincode,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(
                          (_country ?? Countries.defaultCountry) ==
                                  Countries.defaultCountry
                              ? 6
                              : 10,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _field(
                      controller: _landmarkController,
                      label: 'Landmark (optional)',
                      hint: 'e.g. Near City Mall',
                      textCapitalization: TextCapitalization.words,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.patientTeal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppConstants.inputRadius),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          'Save location',
                          style: GoogleFonts.inter(
                              fontSize: AppTypography.bodyLarge,
                              fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      decoration: RequiredFieldLabels.decorate(
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
        isRequired: validator != null,
      ),
    );
  }
}
