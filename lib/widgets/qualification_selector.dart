import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/constants/app_constants.dart';
import '../core/theme/app_colors.dart';
import 'required_field_label.dart';

typedef QualificationDecorationBuilder = InputDecoration Function({
  required String label,
  Widget? prefixIcon,
  String? errorText,
});

/// Doctor qualification picker with preset degrees and an "Other" manual entry.
class QualificationSelector extends FormField<String> {
  QualificationSelector({
    super.key,
    String? initialValue,
    required ValueChanged<String?> onChanged,
    bool isRequired = true,
    Color accentColor = AppColors.doctorBlue,
    String label = 'Qualification',
    Widget? prefixIcon,
    QualificationDecorationBuilder? decorationBuilder,
    bool registrationStyle = false,
    FormFieldValidator<String>? validator,
  }) : super(
          initialValue: _initialFieldValue(initialValue),
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: validator ??
              (isRequired
                  ? (value) {
                      final trimmed = value?.trim() ?? '';
                      if (trimmed.isEmpty) return '$label is required';
                      return null;
                    }
                  : null),
          builder: (state) => _QualificationSelectorBody(
            state: state,
            onChanged: onChanged,
            label: label,
            prefixIcon: prefixIcon,
            accentColor: accentColor,
            isRequired: isRequired,
            decorationBuilder: decorationBuilder,
            registrationStyle: registrationStyle,
            initialCustomValue: _initialCustomValue(initialValue),
          ),
        );

  static String? _initialFieldValue(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (AppConstants.isListedDoctorQualification(trimmed)) return trimmed;
    return AppConstants.otherDoctorQualification;
  }

  static String? _initialCustomValue(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (AppConstants.isListedDoctorQualification(trimmed)) return null;
    return trimmed;
  }
}

class _QualificationSelectorBody extends StatefulWidget {
  const _QualificationSelectorBody({
    required this.state,
    required this.onChanged,
    required this.label,
    required this.prefixIcon,
    required this.accentColor,
    required this.isRequired,
    required this.decorationBuilder,
    required this.registrationStyle,
    required this.initialCustomValue,
  });

  final FormFieldState<String> state;
  final ValueChanged<String?> onChanged;
  final String label;
  final Widget? prefixIcon;
  final Color accentColor;
  final bool isRequired;
  final QualificationDecorationBuilder? decorationBuilder;
  final bool registrationStyle;
  final String? initialCustomValue;

  @override
  State<_QualificationSelectorBody> createState() => _QualificationSelectorBodyState();
}

class _QualificationSelectorBodyState extends State<_QualificationSelectorBody> {
  late String? _selected = widget.state.value;
  late final TextEditingController _otherController = TextEditingController(
    text: widget.initialCustomValue ?? '',
  );

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  void _setValue(String? value) {
    final trimmed = value?.trim().isEmpty == true ? null : value?.trim();
    widget.state.didChange(trimmed);
    widget.onChanged(trimmed);
  }

  void _onDropdownChanged(String? value) {
    setState(() => _selected = value);
    if (value == AppConstants.otherDoctorQualification) {
      _setValue(_otherController.text.trim());
      return;
    }
    _setValue(value);
  }

  void _onOtherChanged(String value) {
    if (_selected == AppConstants.otherDoctorQualification) {
      _setValue(value.trim());
    }
  }

  InputDecoration _decorate({
    required String label,
    String? errorText,
    String? hintText,
  }) {
    if (widget.decorationBuilder != null) {
      return widget.decorationBuilder!(
        label: label,
        prefixIcon: widget.prefixIcon,
        errorText: errorText,
      );
    }
    return RequiredFieldLabels.decorate(
      InputDecoration(hintText: hintText),
      label,
      isRequired: widget.isRequired,
    ).copyWith(errorText: errorText);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final errorText = widget.state.errorText;
    final label = widget.decorationBuilder != null
        ? widget.label
        : (widget.isRequired ? '${widget.label} *' : widget.label);
    final textStyle = widget.registrationStyle
        ? GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _selected,
          isExpanded: true,
          menuMaxHeight: 280,
          borderRadius: BorderRadius.circular(12),
          dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          style: textStyle,
          decoration: _decorate(label: label, errorText: errorText),
          items: AppConstants.doctorQualifications
              .map((q) => DropdownMenuItem(
                    value: q,
                    child: Text(
                      q,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ))
              .toList(),
          onChanged: _onDropdownChanged,
        ),
        if (_selected == AppConstants.otherDoctorQualification) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _otherController,
            style: textStyle,
            textCapitalization: TextCapitalization.characters,
            decoration: _decorate(
              label: 'Enter qualification',
              hintText: 'e.g. MBBS, MD (Medicine)',
              errorText: errorText,
            ),
            onChanged: _onOtherChanged,
          ),
        ],
      ],
    );
  }
}
