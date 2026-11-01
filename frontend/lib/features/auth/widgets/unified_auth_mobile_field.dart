import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/country_phone_codes.dart';
import '../../../core/enums/user_type.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

/// Shared Hero tag for the intro → full mobile auth field transition.
abstract final class UnifiedAuthMobileHero {
  static String tagFor(UserType? role) =>
      'unified-auth-mobile-${role?.name ?? "default"}';
}

/// Split Country Code | Mobile input used on welcome and full mobile auth screens.
class UnifiedAuthMobileField extends StatelessWidget {
  const UnifiedAuthMobileField({
    super.key,
    required this.controller,
    this.countryCode =
        const CountryPhoneCode(country: 'India', dialCode: '+91'),
    this.onCountryChanged,
    this.enableCountryPicker = true,
    this.validator,
    this.onSubmitted,
    this.onChanged,
    this.onTap,
    this.autofocus = false,
    this.readOnly = false,
    this.focusNode,
    this.borderRadius = 12,
    this.fillColor,
    this.borderColor,
    this.boxShadow,
    this.inlineError,
  });

  final TextEditingController controller;
  final CountryPhoneCode countryCode;
  final ValueChanged<CountryPhoneCode>? onCountryChanged;
  final bool enableCountryPicker;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final bool autofocus;
  final bool readOnly;
  final FocusNode? focusNode;
  final double borderRadius;
  final Color? fillColor;
  final Color? borderColor;
  final List<BoxShadow>? boxShadow;
  final String? inlineError;

  void _openCountryPicker(BuildContext context) {
    if (readOnly || !enableCountryPicker) {
      onTap?.call();
      return;
    }
    showModalBottomSheet<CountryPhoneCode>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CountryPickerSheet(
        selected: countryCode,
        onSelected: (code) {
          Navigator.pop(ctx);
          onCountryChanged?.call(code);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasError = inlineError != null && inlineError!.trim().isNotEmpty;
    final resolvedBorderColor = hasError
        ? AppColors.error
        : (borderColor ?? AppColors.borderOf(context));

    final content = Container(
      decoration: BoxDecoration(
        color: fillColor ?? AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(borderRadius),
        border:
            Border.all(color: resolvedBorderColor, width: hasError ? 1.5 : 1.0),
        boxShadow: boxShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openCountryPicker(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 8, 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (countryCode.dialCode == '+91') ...[
                      const _IndiaFlagIcon(),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      countryCode.dialCode,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: AppTypography.bodyMedium,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: AppColors.textSecondaryOf(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: 1,
            height: 28,
            color: resolvedBorderColor.withValues(alpha: 0.7),
          ),
          Expanded(
            child: TextFormField(
              controller: controller,
              focusNode: focusNode,
              autofocus: autofocus,
              readOnly: readOnly,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.telephoneNumber],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              validator: validator,
              onFieldSubmitted: onSubmitted,
              onChanged: onChanged,
              onTap: onTap,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: AppTypography.bodyMedium,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimaryOf(context),
              ),
              decoration: InputDecoration(
                hintText: 'Mobile number',
                hintStyle: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: AppTypography.bodyMedium,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondaryOf(context),
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 16,
                ),
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );

    if (readOnly) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: content,
      );
    }

    if (!hasError) {
      return content;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        content,
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            inlineError!,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.error,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

/// Compact India tricolor for the default +91 dial-code prefix.
class _IndiaFlagIcon extends StatelessWidget {
  const _IndiaFlagIcon();

  static const _width = 16.0;
  static const _height = 11.0;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        width: _width,
        height: _height,
        child: Column(
          children: [
            Expanded(child: Container(color: const Color(0xFFFF9933))),
            Expanded(
              child: ColoredBox(
                color: Colors.white,
                child: Center(
                  child: Container(
                    width: 3.5,
                    height: 3.5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF000080),
                        width: 0.6,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(child: Container(color: const Color(0xFF138808))),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet country picker with search.
class _CountryPickerSheet extends StatefulWidget {
  const _CountryPickerSheet({
    required this.selected,
    required this.onSelected,
  });

  final CountryPhoneCode selected;
  final ValueChanged<CountryPhoneCode> onSelected;

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  final _searchController = TextEditingController();
  List<CountryPhoneCode> _filtered = CountryPhoneCodes.all;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filtered = CountryPhoneCodes.all;
      } else {
        _filtered = CountryPhoneCodes.all
            .where((c) =>
                c.country.toLowerCase().contains(query) ||
                c.dialCode.toLowerCase().contains(query))
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderOf(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
                child: Row(
                  children: [
                    Text(
                      'Select Country Code',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryOf(context),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  autofocus: false,
                  decoration: InputDecoration(
                    hintText: 'Search country or code...',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                    filled: true,
                    fillColor: isDark
                        ? const Color(0xFF0F172A)
                        : const Color(0xFFF1F5F9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: _filtered.length,
                  itemBuilder: (context, index) {
                    final item = _filtered[index];
                    final isSelected =
                        item.dialCode == widget.selected.dialCode &&
                            item.country == widget.selected.country;

                    return ListTile(
                      dense: true,
                      title: Text(
                        item.country,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: AppColors.textPrimaryOf(context),
                        ),
                      ),
                      trailing: Text(
                        item.dialCode,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? AppColors.patientTeal
                              : AppColors.textSecondaryOf(context),
                        ),
                      ),
                      selected: isSelected,
                      selectedTileColor:
                          AppColors.patientTeal.withValues(alpha: 0.08),
                      onTap: () => widget.onSelected(item),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
