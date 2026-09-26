import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/constants/country_phone_codes.dart';
import '../core/theme/app_colors.dart';
import '../core/validators/form_validators.dart';
import 'required_field_label.dart';
import '../core/theme/app_typography.dart';

class PhoneNumberField extends StatefulWidget {
  const PhoneNumberField({
    super.key,
    required this.controller,
    this.initialPhone,
    this.initialDialCode,
    this.labelText,
    this.hintText,
    this.validator,
    this.decoration,
    this.enabled = true,
    this.onChanged,
    this.onDialCodeChanged,
    this.suffixIcon,
    this.counterText,
    this.maxLocalLength,
    this.focusNode,
    this.readOnly = false,
    this.onTap,
    this.isRequired,
    this.helperText,
  });

  final TextEditingController controller;
  final String? initialPhone;
  final String? initialDialCode;
  final String? labelText;
  final String? hintText;
  final String? Function(String?)? validator;
  final InputDecoration? decoration;
  final bool enabled;
  final VoidCallback? onChanged;
  final ValueChanged<String>? onDialCodeChanged;
  final Widget? suffixIcon;
  final String? counterText;
  final int? maxLocalLength;
  final FocusNode? focusNode;
  final bool readOnly;
  final VoidCallback? onTap;
  final bool? isRequired;
  final String? helperText;

  @override
  State<PhoneNumberField> createState() => _PhoneNumberFieldState();
}

class _PhoneNumberFieldState extends State<PhoneNumberField> {
  late String _dialCode =
      widget.initialDialCode ?? CountryPhoneCodes.defaultDialCode;

  String get dialCode => _dialCode;

  String get fullNumber =>
      FormValidators.formatFullPhone(_dialCode, widget.controller.text);

  @override
  void initState() {
    super.initState();
    if (widget.initialPhone != null && widget.initialPhone!.trim().isNotEmpty) {
      final parsed = FormValidators.parsePhone(widget.initialPhone);
      _dialCode = parsed.dialCode;
    }
  }

  void _pickCountryCode() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _CountryCodePickerSheet(selectedDialCode: _dialCode),
    );

    if (selected != null && mounted) {
      setState(() => _dialCode = selected);
      widget.onDialCodeChanged?.call(selected);
      widget.onChanged?.call();
    }
  }

  int get _maxLength {
    if (widget.maxLocalLength != null) return widget.maxLocalLength!;
    return _dialCode == CountryPhoneCodes.defaultDialCode ? 10 : 15;
  }

  @override
  Widget build(BuildContext context) {
    final baseDecoration = widget.decoration ?? const InputDecoration();
    final hasExistingLabel = baseDecoration.label != null;
    final label = widget.labelText ?? baseDecoration.labelText ?? '';
    final isRequired = widget.isRequired ?? widget.validator != null;

    final InputDecoration decoratedWithPrefix = baseDecoration.copyWith(
      hintText: widget.hintText ?? baseDecoration.hintText,
      helperText: widget.helperText ?? baseDecoration.helperText,
      suffixIcon: widget.suffixIcon ?? baseDecoration.suffixIcon,
      counterText: widget.counterText ?? baseDecoration.counterText,
      prefixIcon: null,
      prefix: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          onTap: widget.enabled && !widget.readOnly ? _pickCountryCode : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _dialCode,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.bodyMedium,
                    fontWeight: FontWeight.w600,
                    color: widget.enabled
                        ? AppColors.textPrimaryOf(context)
                        : AppColors.textSecondaryOf(context),
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  size: 20,
                  color: widget.enabled
                      ? AppColors.textSecondaryOf(context)
                      : AppColors.textSecondaryOf(context)
                          .withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final mergedDecoration = hasExistingLabel
        ? decoratedWithPrefix
        : RequiredFieldLabels.decorate(
            decoratedWithPrefix,
            label,
            isRequired: isRequired && label.isNotEmpty,
          );

    return TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      readOnly: widget.readOnly,
      showCursor: !widget.readOnly,
      enableInteractiveSelection: !widget.readOnly,
      onTap: widget.onTap,
      enabled: widget.enabled,
      keyboardType: TextInputType.phone,
      inputFormatters: [
        _PhoneNumberInputFormatter(
          dialCode: _dialCode,
          maxLength: _maxLength,
        ),
      ],
      decoration: mergedDecoration,
      validator: widget.validator ??
          (value) => FormValidators.phoneLocal(value, dialCode: _dialCode),
      onChanged: (_) => widget.onChanged?.call(),
    );
  }
}

/// Formatter that strips redundant dial codes and leading zeroes when pasted,
/// ensuring the full subscriber number fits within [maxLength].
class _PhoneNumberInputFormatter extends TextInputFormatter {
  _PhoneNumberInputFormatter({
    required this.dialCode,
    required this.maxLength,
  });

  final String dialCode;
  final int maxLength;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text;
    if (text.isEmpty) return newValue;

    // Retain only digits
    var digits = text.replaceAll(RegExp(r'\D'), '');
    final cleanDial = dialCode.replaceAll(RegExp(r'\D'), '');

    // Strip dial code if user typed or pasted with country code (e.g. 919876543210 -> 9876543210)
    while (cleanDial.isNotEmpty &&
        digits.startsWith(cleanDial) &&
        digits.length > cleanDial.length) {
      digits = digits.substring(cleanDial.length);
    }

    // Strip leading zeroes (e.g. 09876543210 -> 9876543210)
    while (digits.startsWith('0') && digits.length > 1) {
      digits = digits.substring(1);
    }

    // Enforce max length
    if (digits.length > maxLength) {
      digits = digits.substring(0, maxLength);
    }

    return TextEditingValue(
      text: digits,
      selection: TextSelection.collapsed(offset: digits.length),
    );
  }
}

class _CountryCodePickerSheet extends StatefulWidget {
  const _CountryCodePickerSheet({required this.selectedDialCode});

  final String selectedDialCode;

  @override
  State<_CountryCodePickerSheet> createState() =>
      _CountryCodePickerSheetState();
}

class _CountryCodePickerSheetState extends State<_CountryCodePickerSheet> {
  final _searchController = TextEditingController();
  late List<CountryPhoneCode> _filtered = CountryPhoneCodes.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filter(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = CountryPhoneCodes.all;
        return;
      }
      _filtered = CountryPhoneCodes.all
          .where(
            (entry) =>
                entry.country.toLowerCase().contains(q) ||
                entry.dialCode.contains(q),
          )
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.75;

    return SafeArea(
      child: SizedBox(
        height: maxHeight,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Select country code',
                style: GoogleFonts.inter(
                  fontSize: AppTypography.headlineSmall,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search country or code',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: _filter,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _filtered.length,
                itemBuilder: (context, index) {
                  final entry = _filtered[index];
                  final selected = entry.dialCode == widget.selectedDialCode;
                  return ListTile(
                    title: Text(entry.country),
                    trailing: Text(
                      entry.dialCode,
                      style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                    ),
                    selected: selected,
                    onTap: () => Navigator.pop(context, entry.dialCode),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
