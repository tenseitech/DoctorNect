import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/validators/form_validators.dart';
import '../../../widgets/required_field_label.dart';
import '../models/ambulance_models.dart';
import '../../../core/theme/app_typography.dart';

class AmbulanceFormSectionTitle extends StatelessWidget {
  const AmbulanceFormSectionTitle(
      {super.key, required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFFDC2626)),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.inter(
            fontSize: AppTypography.bodyLarge,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimaryOf(context),
          ),
        ),
      ],
    );
  }
}

class AmbulanceFormField extends StatelessWidget {
  const AmbulanceFormField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.hint,
    this.validator,
    this.keyboard,
    this.formatters,
    this.maxLines = 1,
    this.capitalization = TextCapitalization.words,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? hint;
  final String? Function(String?)? validator;
  final TextInputType? keyboard;
  final List<TextInputFormatter>? formatters;
  final int maxLines;
  final TextCapitalization capitalization;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboard,
      inputFormatters: formatters,
      maxLines: maxLines,
      textCapitalization: capitalization,
      style: GoogleFonts.inter(fontSize: AppTypography.bodyMedium),
      decoration: RequiredFieldLabels.decorate(
        InputDecoration(
          hintText: hint,
          prefixIcon:
              Icon(icon, size: 20, color: AppColors.textSecondaryOf(context)),
          filled: true,
          fillColor: AppColors.surfaceOf(context),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.borderOf(context)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.borderOf(context)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
        label,
        isRequired: validator != null,
      ),
    );
  }
}

class AmbulanceTypeField extends StatelessWidget {
  const AmbulanceTypeField(
      {super.key, required this.value, required this.onChanged});

  final AmbulanceType value;
  final ValueChanged<AmbulanceType> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<AmbulanceType>(
      initialValue: value,
      decoration: RequiredFieldLabels.decorate(
        InputDecoration(
          prefixIcon: Icon(Icons.emergency_outlined,
              size: 20, color: AppColors.textSecondaryOf(context)),
          filled: true,
          fillColor: AppColors.surfaceOf(context),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.borderOf(context)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
          ),
        ),
        'Ambulance Type',
        isRequired: true,
      ),
      items: AmbulanceType.values.map((type) {
        final label = switch (type) {
          AmbulanceType.bls => 'BLS (Basic Life Support)',
          AmbulanceType.als => 'ALS (Advanced Life Support)',
          AmbulanceType.icu => 'ICU Ambulance',
          AmbulanceType.patientTransport => 'Patient Transport',
        };
        return DropdownMenuItem(value: type, child: Text(label));
      }).toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class AmbulanceFormToggleRow extends StatelessWidget {
  const AmbulanceFormToggleRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                  fontSize: AppTypography.bodyMedium,
                  fontWeight: FontWeight.w500),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFFDC2626),
          ),
        ],
      ),
    );
  }
}

String? ambulanceRequiredField(String? v) =>
    v == null || v.trim().isEmpty ? 'This field is required' : null;

String? ambulanceVehicleNumberField(String? value) =>
    FormValidators.vehicleNumber(value);

final ambulanceVehicleNumberFormatters = [
  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-]')),
  LengthLimitingTextInputFormatter(13),
];

RegisteredAmbulance buildAmbulanceDraftFromControllers({
  required TextEditingController serviceNameCtrl,
  required TextEditingController ownerNameCtrl,
  required TextEditingController driverNameCtrl,
  required TextEditingController phoneCtrl,
  required TextEditingController vehicleNumberCtrl,
  required AmbulanceType ambulanceType,
  required TextEditingController cityCtrl,
  required TextEditingController serviceAreasCtrl,
  required TextEditingController baseAddressCtrl,
  required TextEditingController licenseCtrl,
  required TextEditingController insuranceCtrl,
  required bool hasOxygen,
  required bool hasVentilator,
  required bool hasStretcher,
  required bool is24x7,
  required TextEditingController rateCtrl,
  String? formattedPhone,
}) {
  final areas = serviceAreasCtrl.text
      .split(RegExp(r'[,\n]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  return RegisteredAmbulance(
    id: 'amb-reg-${DateTime.now().millisecondsSinceEpoch}',
    serviceName: serviceNameCtrl.text.trim(),
    ownerName: ownerNameCtrl.text.trim(),
    driverName: driverNameCtrl.text.trim(),
    phone: formattedPhone ?? phoneCtrl.text.trim(),
    vehicleNumber:
        FormValidators.normalizeVehicleNumber(vehicleNumberCtrl.text),
    ambulanceType: ambulanceType,
    city: cityCtrl.text.trim(),
    serviceAreas: areas,
    baseAddress: baseAddressCtrl.text.trim(),
    licenseNumber: licenseCtrl.text.trim(),
    insuranceNumber: insuranceCtrl.text.trim(),
    hasOxygen: hasOxygen,
    hasVentilator: hasVentilator,
    hasStretcher: hasStretcher,
    is24x7: is24x7,
    ratePerKm: double.tryParse(rateCtrl.text.trim()),
    available: true,
    createdAt: DateTime.now(),
  );
}
