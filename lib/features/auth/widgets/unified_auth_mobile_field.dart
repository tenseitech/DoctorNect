import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/country_phone_codes.dart';
import '../../../core/enums/user_type.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

/// Shared Hero tag for the intro → full mobile auth field transition.
abstract final class UnifiedAuthMobileHero {
  static String tagFor(UserType role) => 'unified-auth-mobile-${role.name}';
}

/// Split +91 | mobile input used on intro and full mobile auth screens.
class UnifiedAuthMobileField extends StatelessWidget {
  const UnifiedAuthMobileField({
    super.key,
    required this.controller,
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
  });

  final TextEditingController controller;
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

  @override
  Widget build(BuildContext context) {
    final resolvedBorderColor = borderColor ?? AppColors.borderOf(context);

    return Container(
      decoration: BoxDecoration(
        color: fillColor ?? AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: resolvedBorderColor),
        boxShadow: boxShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 16, 8, 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _IndiaFlagIcon(),
                const SizedBox(width: 5),
                Text(
                  CountryPhoneCodes.defaultDialCode,
                  style: GoogleFonts.inter(
                    fontSize: AppTypography.bodyMedium,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryOf(context),
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: AppColors.textSecondaryOf(context),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 28,
            color: resolvedBorderColor,
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
              style: GoogleFonts.inter(
                fontSize: AppTypography.bodyMedium,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimaryOf(context),
              ),
              decoration: InputDecoration(
                hintText: 'Mobile number',
                hintStyle: GoogleFonts.inter(
                  fontSize: AppTypography.bodyMedium,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textSecondaryOf(context),
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                isDense: true,
              ),
            ),
          ),
        ],
      ),
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
            Expanded(
              child: Container(color: const Color(0xFFFF9933)),
            ),
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
            Expanded(
              child: Container(color: const Color(0xFF138808)),
            ),
          ],
        ),
      ),
    );
  }
}
